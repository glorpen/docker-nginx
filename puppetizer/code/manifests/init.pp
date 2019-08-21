class puppetizer_main (
  String $nginx_version,
  Hash $servers = {},
  Hash $auth_basic = {},
  String $nginx_access_log = '/proc/1/fd/1',
  String $nginx_error_log = '/proc/1/fd/2',
  Optional[String] $consul_addr = undef,
  Optional[String] $consul_token = undef,
  String $letsencrypt_consul_key = 'letsencrypt',
  Hash[String, Struct[{'fullchain'=>String, 'privkey'=>String}]] $consul_certnames = {},
  Optional[String] $letsencrypt_url = undef
){
  include ::stdlib

  $auth_dir = '/etc/nginx/auth'
  $ssl_path = '/usr/local/share/ssl'

  $letsencrypt_certnames = delete_undef_values(flatten($servers.map | $name, $config | {
    $config['letsencrypt_certname']
  }))

  include ::puppetizer_main::setup

  if $::puppetizer['running'] {
    $_supported_params = [
      'ssl_redirect', 'auth_basic_source', 'locations', 'ipv6_listen_options',
      'consul_certname', 'letsencrypt_certname'
    ]

    $servers.each | $name, $config | {
      $resource_config = Hash($_supported_params.map | $v | {
        [$v, $config[$v]]
      })
      ::puppetizer_main::server { $name:
        config => delete($config, $_supported_params),
        *      => $resource_config
      }
    }
  }

  $auth_basic.each | $name, $users | {
    ::puppetizer_main::auth_basic { $name:
      users => $users
    }
  }

  if $consul_addr {
    include ::puppetizer_main::consul_template
  }
}
