class puppetizer_main (
  Hash $servers = {},
  Optional[String] $letsencrypt_email = undef,
  Hash $auth_basic = {},
  String $letsencrypt_version,
  String $nginx_version
){
  # https://github.com/certbot/certbot/blob/master/certbot-nginx/certbot_nginx/options-ssl-nginx.conf
  
  $certbot_webroot = '/var/nginx/certboot'
  $auth_dir = '/etc/nginx/auth'
  $le_live_dir = '/etc/letsencrypt/live'
  
  include ::stdlib
  include ::puppetizer_main::setup
  
  if $::puppetizer['running'] {
    $_supported_params = [
      'ssl_letsencrypt', 'ssl_redirect', 'auth_basic_source', 'locations',
      'ipv6_listen_options'
    ]
    
    $servers.each | $name, $config | {
      $resource_config = Hash($_supported_params.map | $v | {
        [$v, $config[$v]]
      })
      ::puppetizer_main::server { $name:
        config => delete($config, $_supported_params),
        * => $resource_config
      }
    }
  }
  
  $auth_basic.each | $name, $users | {
    ::puppetizer_main::auth_basic { $name:
      users => $users
    }
  }
}
