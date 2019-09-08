define puppetizer_main::server(
  Hash $config,
  Enum['present','absent'] $ensure = 'present',
  Boolean $ssl_redirect = false,
  Optional[String] $auth_basic_source = undef,
  Hash $locations = {},
  String $ipv6_listen_options = '',
  Optional[String] $consul_certname = undef,
  Optional[String] $letsencrypt_certname = undef
  Array[String] $resolver = ['127.0.0.11'];
){
  if $ensure == 'present' {
    if $letsencrypt_certname {
      $_config_letsencrypt = {
        'ssl_redirect' => false
      }
    } else {
      $_config_letsencrypt = {
        'ssl_redirect' => $ssl_redirect
      }
    }

    if $consul_certname {
      $_config_ssl = {
        ssl_cert => "${puppetizer_main::ssl_path}/${consul_certname}/fullchain.pem",
        ssl_key  => "${puppetizer_main::ssl_path}/${consul_certname}/privkey.pem",
      }
    } elsif $letsencrypt_certname {
      $_config_ssl = {
        ssl_cert => "${puppetizer_main::ssl_path}/${letsencrypt_certname}/fullchain.pem",
        ssl_key  => "${puppetizer_main::ssl_path}/${letsencrypt_certname}/privkey.pem",
      }
    } else {
      $_config_ssl = {}
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
        # make location names unique by design
        $location_name = "${name}-${k}"
        $auth_source = $v['auth_basic_source']
        if $auth_source {
          Puppetizer_main::Auth_basic[$auth_source]->
          Nginx::Resource::Location[$location_name]

          $_v = merge(delete($v, ['auth_basic_source']), {
            'auth_basic_user_file' => "${::puppetizer_main::auth_dir}/${auth_source}.passwd"
          })
        } else {
          $_v = $v
        }
        [$location_name, merge($_v, {
          'location' => $k
        })]
      })
    }

    $_config_defaults = {
      'ipv6_enable' => true,
      'http2'       => 'on',
      'access_log'  => 'absent',
      'error_log'   => 'absent',
    }

    $_config = merge(
      $_config_defaults,
      $config,
      $_config_ssl,
      $_config_letsencrypt,
      $_config_auth,
      $_config_locations
    )

    nginx::resource::server { $name:
      use_default_location => false,
      ipv6_listen_options  => $ipv6_listen_options,
      resolver             => $resolver,
      *                    => $_config
    }

    if $letsencrypt_certname {
      nginx::resource::location {"letsencrypt ${name}":
        ensure         => present,
        server         => $name,
        location       => '/.well-known/',
        ssl            => false,
        proxy          => $puppetizer_main::letsencrypt_url,
        location_allow => ['all'],
      }

      if $ssl_redirect {
        nginx::resource::location {"letsencrypt ${name} ssl-redirect":
          ensure              => present,
          server              => $name,
          priority            => 550,
          ssl                 => false,
          location            => '/',
          location_cfg_append => {
            'return' => '301 https://$host$request_uri'
          }
        }
      }
    }
  } else {
    nginx::resource::server { $name:
      ensure => $ensure
    }
  }
}
