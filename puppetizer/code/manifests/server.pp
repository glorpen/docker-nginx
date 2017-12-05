define puppetizer_main::server(
  Boolean $ssl_letsencrypt = false,
  Boolean $ssl_redirect = false,
  Optional[String] $auth_basic_source = undef,
  Hash $locations = {},
  Hash $config
){
  if $ssl_letsencrypt {
    
    # since nginx will not start if there is not ssl certs when ssl is enabled
    # we create temporary self-signed certs
    # and later replace it with valid ones
    
    $le_path = "${::puppetizer_main::le_live_dir}/${name}"
    $le_cert_path = "${le_path}/fullchain.pem"
    $le_key_path = "${le_path}/privkey.pem"
    
    file {$le_path:
      ensure => directory,
      mode => 'a=rx,u+w',
      require => File[$::puppetizer_main::le_live_dir],
    }->
    exec { "letsencrypt temp certs for ${name}":
      # create until letsencrypt generates cert
      command => "/bin/openssl req -x509 -newkey rsa:4096 -nodes -keyout ${le_key_path} -out ${le_cert_path} -days 1 -subj '/C=XX/ST=Temporary/L=Temporary/O=Temporary/OU=Org/CN=${name}'",
      creates => "${le_path}/chain.pem", # created by letsencrypt
      before => Nginx::Resource::Server[$name],
      require => Class['letsencrypt::install'] # needs openssl
    }
    # carry on even if cert is expired, eg. from previous run
    
    $_config_letsencrypt = {
      ssl_cert    => $le_cert_path,
      ssl_key     => $le_key_path,
      ssl_redirect => false
    }
  } else {
    $_config_letsencrypt = {
      'ssl_redirect' => $ssl_redirect
    }
  }
  
  if $auth_basic_source {
    $_config_auth = {
      'auth_basic_user_file' => "${::puppetizer_main::auth_dir}/${auth_basic_source}.passwd"
    }
    
    Puppetizer_main::Auth_basic[$auth_basic_source]->
    Nginx::Resource::Server[$name]
  } else {
    $_config_auth = {}
  }
  
  $_config_locations = {
    'locations' => Hash($locations.map | $k, $v | {
      $auth_source = $v['auth_basic_source']
      if $auth_source {
        Puppetizer_main::Auth_basic[$auth_source]->
        Nginx::Resource::Location[$k]
        
        $_v = merge(delete($v, ['auth_basic_source']), {
          'auth_basic_user_file' => "${::puppetizer_main::auth_dir}/${auth_source}.passwd"
        })
      } else {
        $_v = $v
      }
      [$k, $_v]
    })
  }
  
  $_config = merge(
    $config,
    $_config_letsencrypt,
    $_config_auth,
    $_config_locations
  )
  
  
  
  nginx::resource::server { $name:
    use_default_location => false,
    * => $_config
  }
  
  if $ssl_letsencrypt {
    $webroot = "${::puppetizer_main::certbot_webroot}/${name}"
    
    file { $webroot:
      ensure => directory,
      require => File[$::puppetizer_main::certbot_webroot],
      backup => false,
      mode => 'a=rx,u+w'
    }
  
    nginx::resource::location {"letsencrypt ${name}":
      ensure => present,
      server => $name,
      location => '/.well-known/',
      ssl => false,
      www_root => "${::puppetizer_main::certbot_webroot}/${name}",
      location_allow => ['all'],
      require => File[$webroot]
    }
    
    if $ssl_redirect {
      nginx::resource::location {"letsencrypt ${name} ssl-redirect":
        ensure => present,
        server => $name,
        priority => 550,
        ssl => false,
        location => "/",
        location_cfg_append => {
          "return" => '301 https://$host$request_uri'
        }
      }
    }
    
    # remove temporary certs so letsencrypt can create directory
    exec { "letsencrypt remove tmp certificates for ${name}":
      command => "/bin/rm -rf ${le_path}",
      creates => "${le_path}/chain.pem",
      require => Nginx::Resource::Server[$name]
    }->
    letsencrypt::certonly { $name:
      plugin => 'webroot',
      webroot_paths => ["${::puppetizer_main::certbot_webroot}/${name}"],
      additional_args => ['--test-cert', '--non-interactive'],
      manage_cron => true,
      cron_success_command => 'nginx -s reload',
      require => [Class['nginx'], Nginx::Resource::Location["letsencrypt ${name}"]]
    }
  }
}
