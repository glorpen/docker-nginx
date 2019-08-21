class puppetizer_main::setup {

  class { 'nginx':
    service_ensure  => $::puppetizer['running'],
    package_ensure  => $::puppetizer_main::nginx_version,
    http_access_log => $::puppetizer_main::nginx_access_log,
    nginx_error_log => $::puppetizer_main::nginx_error_log
  }
  ->package { [
    'nginx-mod-http-set-misc',
    'nginx-mod-http-headers-more',
    'nginx-mod-http-upload-progress',
    'nginx-mod-http-lua',
    'nginx-mod-http-lua-upstream'
  ]:
    ensure => $::puppetizer_main::nginx_version
  }

  package { 'openssl':
    ensure => present
  }

  puppetizer::service { 'nginx':
    run_content => "#!/bin/sh -e\nexec /usr/sbin/nginx -g 'daemon off;' -c /etc/nginx/nginx.conf",
  }

  file { $::puppetizer_main::auth_dir:
    ensure => directory,
    purge  => true,
    force  => true,
    notify => Service['nginx']
  }

  file { '/usr/local/bin/nginx-ssl-seed':
    ensure  => present,
    mode    => 'a=rx,u+w',
    content => epp('puppetizer_main/seed-ssl.sh.epp', {
      'certnames'       => $puppetizer_main::letsencrypt_certnames + keys($puppetizer_main::consul_certnames),
      'consul_ssl_path' => $puppetizer_main::ssl_path
    })
  }
  exec { 'puppetizer ssl seed':
    command     => '/usr/local/bin/nginx-ssl-seed',
    # refreshonly => true
  }

  Exec['puppetizer ssl seed']
  ->Service['nginx']
}
