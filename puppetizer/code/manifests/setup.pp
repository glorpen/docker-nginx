class puppetizer_main::setup {
  package { ['epel-release', 'cronie']: }->
  class { 'letsencrypt':
    email => $::puppetizer_main::letsencrypt_email,
    manage_config => $::puppetizer['running'],
    configure_epel => false,
    package_ensure => '0.19.0'
  }
  
  class { 'nginx':
    service_ensure => $::puppetizer['running'],
    package_ensure => '1.12.2'
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
  
  Service <| title == 'nginx' |> {
    provider => 'base',
    start => "/usr/sbin/nginx -t -c /etc/nginx/nginx.conf && /usr/sbin/nginx -c /etc/nginx/nginx.conf",
    stop => "/usr/sbin/nginx -s stop && while /bin/pkill -f -0 'nginx: master'; do sleep 0.5s; done",
    restart => "/usr/sbin/nginx -s reload",
    status => "/bin/pkill -f -0 'nginx: master'",
  }
  
  service { 'cron':
    ensure => $::puppetizer['running'],
    provider => 'base',
    start => '/usr/sbin/crond -s',
    stop => '/bin/pkill crond',
    status => "/bin/pkill -0 crond",
  }
  
  puppetizer::health { 'nginx':
    command => 'pkill -f -0 "nginx: master"; exit $?'
  }
  
  file { $::puppetizer_main::auth_dir:
    ensure => directory
  }
  
  if $::puppetizer['running'] {
    file {$::puppetizer_main::le_live_dir:
      ensure => directory,
      mode => 'a=rx,u+w',
      require => File['/etc/letsencrypt']
    }
  }
}
