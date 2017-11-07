class puppetizer_main (
  Hash $servers = {},
  Optional[String] $letsencrypt_email = undef 
){
  # https://github.com/certbot/certbot/blob/master/certbot-nginx/certbot_nginx/options-ssl-nginx.conf
  
  include ::stdlib
  
  package { ['epel-release', 'cronie']: }->
  class { 'letsencrypt':
    email => $letsencrypt_email,
    manage_config => $::puppetizer['running'],
    configure_epel => false,
    package_ensure => '0.19.0'
  }
  
  class { 'nginx':
    service_ensure => $::puppetizer['running'],
    package_ensure => '1.12.2'
  }
    
  $certbot_webroot = '/var/nginx/certboot'
  file { $certbot_webroot:
    ensure => directory,
    require => [Class['nginx'], Class['letsencrypt']],
    purge => true,
    force => true,
    backup => false,
    recurse => true,
    mode => 'a=rx,u+w'
  }

  if $::puppetizer['running'] {
    file {'/etc/letsencrypt/live':
      ensure => directory,
      mode => 'a=rx,u+w',
      require => File['/etc/letsencrypt']
    }
    
    $servers.each | $name, $config | {
      
      $use_letsencrypt = $config['ssl_letsencrypt'] == true
      
      if $use_letsencrypt {
        
        # since nginx will not start if there is not ssl certs when ssl is enabled
        # we create temporary self-signed certs
        # and later replace it with valid ones
        
        $le_path = "/etc/letsencrypt/live/${name}"
        $le_cert_path = "${le_path}/fullchain.pem"
        $le_key_path = "${le_path}/privkey.pem"
        
        file {$le_path:
          ensure => directory,
          mode => 'a=rx,u+w',
          require => File['/etc/letsencrypt/live'],
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
        }
      } else {
        $_config_letsencrypt = {}
      }
      
      $_config = merge(
        delete($config, ['ssl_letsencrypt']),
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
  
  resources{"cron": purge => true}
  
  Service <| title == 'nginx' |> {
    provider => 'base',
    start => "/usr/sbin/nginx -t -c /etc/nginx/nginx.conf && /usr/sbin/nginx -c /etc/nginx/nginx.conf",
    stop => "/usr/sbin/nginx -s stop && sleep 1s",
    restart => "/usr/sbin/nginx -s reload",
    status => "/bin/pkill -0 nginx",
  }
  
  service { 'cron':
    ensure => $::puppetizer['running'],
    provider => 'base',
    start => '/usr/sbin/crond -s',
    stop => '/bin/pkill crond',
    status => "/bin/pkill -0 crond",
  }
  
  puppetizer::health { 'nginx':
    command => '/bin/pkill -0 nginx; exit $?'
  }
  
  # shutdown cronie service
  # shutdown nginx service
  #--test-cert
}
