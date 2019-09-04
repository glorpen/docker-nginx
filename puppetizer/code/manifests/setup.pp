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
    start_content => @("END"/)
      #!/bin/sh -e

      cleanup(){
        echo "Cleaning up"
        kill -SIGQUIT %1 &>/dev/null || true
        exit 0;
      }

      trap '{ cleanup; }' INT TERM

      for i in \$(seq 1 ${puppetizer_main::time_to_wait_for_domains});
      do
        echo "Checking for working config (try \$i of ${puppetizer_main::time_to_wait_for_domains})"
        /usr/sbin/nginx -g 'daemon off;' -t -c /etc/nginx/nginx.conf && break
        sleep 1s
      done

      /usr/sbin/nginx -g 'daemon off;' -c /etc/nginx/nginx.conf &

      wait

      | END
    ,
    stop_content => @("END"/)
      #!/bin/sh -e
      exec kill -TERM \$1
      | END
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
