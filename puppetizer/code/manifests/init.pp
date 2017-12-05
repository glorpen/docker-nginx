class puppetizer_main (
  Hash $servers = {},
  Optional[String] $letsencrypt_email = undef,
  Hash $auth_basic = {}
){
  # https://github.com/certbot/certbot/blob/master/certbot-nginx/certbot_nginx/options-ssl-nginx.conf
  
  $certbot_webroot = '/var/nginx/certboot'
  $auth_dir = '/etc/nginx/auth'
  $le_live_dir = '/etc/letsencrypt/live'
  
  include ::stdlib
  include ::puppetizer_main::setup
  
  if $::puppetizer['running'] {
    
    $servers.each | $name, $config | {
      
      $use_letsencrypt = $config['ssl_letsencrypt'] == true
      $ssl_redirect = $config['ssl_redirect'] == true;
      
      if $use_letsencrypt {
        
        # since nginx will not start if there is not ssl certs when ssl is enabled
        # we create temporary self-signed certs
        # and later replace it with valid ones
        
        $le_path = "${le_live_dir}/${name}"
        $le_cert_path = "${le_path}/fullchain.pem"
        $le_key_path = "${le_path}/privkey.pem"
        
        file {$le_path:
          ensure => directory,
          mode => 'a=rx,u+w',
          require => File[$le_live_dir],
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
      
      $_config = merge(
        delete($config, ['ssl_letsencrypt', 'ssl_redirect']),
        $_config_letsencrypt
      )
      
      nginx::resource::server { $name:
        use_default_location => false,
        * => $_config
      }
      
      if $use_letsencrypt {
        $webroot = "${certbot_webroot}/${name}"
        
        file { $webroot:
          ensure => directory,
          require => File[$certbot_webroot],
          backup => false,
          mode => 'a=rx,u+w'
        }
      
        nginx::resource::location {"letsencrypt ${name}":
          ensure => present,
          server => $name,
          location => '/.well-known/',
          ssl => false,
          www_root => "${certbot_webroot}/${name}",
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
          webroot_paths => ["${certbot_webroot}/${name}"],
          additional_args => ['--test-cert', '--non-interactive'],
          manage_cron => true,
          cron_success_command => 'nginx -s reload',
          require => [Class['nginx'], Nginx::Resource::Location["letsencrypt ${name}"]]
        }
      }
    }
  }
  
  $auth_basic.each | $name, $users | {
    ::puppetizer_main::auth_basic { $name:
      users => $users
    }
  }
}
