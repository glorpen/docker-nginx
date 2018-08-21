class puppetizer_main::setup {
  package { [
      'openssl', 'python3',
      'py3-cffi', 'py3-six', 'py3-requests', 'py3-cryptography', 'py3-configobj',
      'py3-openssl', 'py3-tz', 'py3-zope-interface', 'py3-pbr', 'py3-rfc3339',
      'py3-configargparse', 'py3-mock',
    ]:
    ensure => 'present'
  }->
  package { 'certbot':
    provider => 'pip3',
    ensure => $::puppetizer_main::letsencrypt_version
  }->
  class { 'letsencrypt':
    email => $::puppetizer_main::letsencrypt_email,
    manage_config => $::puppetizer['running'],
    config => {},
    manage_install => false,
    install_method => 'package',
    package_command => 'certbot'
  }

  class { 'nginx':
    service_ensure => $::puppetizer['running'],
    package_ensure => $::puppetizer_main::nginx_version,
    http_access_log => $::puppetizer_main::nginx_access_log,
    nginx_error_log => $::puppetizer_main::nginx_error_log
  }->
  package { [
    'nginx-mod-http-set-misc',
    'nginx-mod-http-headers-more',
    'nginx-mod-http-upload-progress',
    'nginx-mod-http-lua',
    'nginx-mod-http-lua-upstream'
  ]:
    ensure => $::puppetizer_main::nginx_version
  }

  file { $::puppetizer_main::certbot_webroot:
    ensure => directory,
    require => [Class['nginx'], Class['letsencrypt']],
    purge => true,
    force => true,
    backup => false,
    recurse => true,
    mode => 'a=rx,u+w'
  }
  
  resources{"cron": purge => true}
  
  #dcron doesn't support ENV and setting VENV is not needed
  #Cron <| |> {
  #  environment => undef
  #}
  
  cron { 'clean letsencrypt logs':
    command => 'rm /var/log/letsencrypt/letsencrypt.log.*',
    user    => 'root',
    hour    => 0,
    minute  => 0
  }
  
  Service <| title == 'nginx' |> {
    provider => 'base',
    start => "/usr/sbin/nginx -t -c /etc/nginx/nginx.conf && /usr/sbin/nginx -c /etc/nginx/nginx.conf",
    stop => 'pid=$(cat /run/nginx.pid); /usr/sbin/nginx -s stop && while /bin/kill -0 $pid &> /dev/null; do sleep 0.5s; done',
    restart => '/usr/sbin/nginx -s reload',
    status => 'test -f /run/nginx.pid && /bin/kill -0 $(cat /run/nginx.pid)',
  }
  
  service { 'cron':
    ensure => $::puppetizer['running'],
    provider => 'base',
    start => '/usr/sbin/crond -L /proc/1/fd/1',
    stop => '/bin/kill $(cat /run/crond.pid)',
    status => "test -f /run/crond.pid && /bin/kill -0 $(cat /run/crond.pid)",
  }
  
  puppetizer::health { 'nginx':
    command => 'test -f /run/nginx.pid && /bin/kill -0 $(cat /run/nginx.pid); exit $?'
  }
  
  file { $::puppetizer_main::auth_dir:
    ensure => directory,
    purge => true,
    force => true,
    notify => Service['nginx']
  }
  
  if $::puppetizer['running'] {
    file {$::puppetizer_main::le_live_dir:
      ensure => directory,
      mode => 'a=rx,u+w',
      require => File['/etc/letsencrypt'],
      purge => true,
      force => true,
      recurse => true,
      recurselimit => 1
    }
  } else {
    # clean pip cache
    Package <| |>->
    file { '/root/.cache':
      ensure => absent,
      backup => false,
      force => true
    }
  }
}
