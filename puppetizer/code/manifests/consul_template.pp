class puppetizer_main::consul_template {
  $cmd = 'sh -c "nginx -s reload || true"'
  $_files = ['fullchain', 'privkey']

  $items = flatten($puppetizer_main::letsencrypt_certnames.map | $certname | {
    $_files.map | $f | {
      {'name' => $certname, 'key' => "${puppetizer_main::letsencrypt_consul_key}/${certname}/${f}", 'target' => $f}
    }
  }) + flatten($puppetizer_main::consul_certnames.map | $certname, $info | {
    $_files.map | $f | {
      {'name' => $certname, 'key' => "${puppetizer_main::letsencrypt_consul_key}/${certname}/${info['fullchain']}", 'target' => $f}
    }
  })

  $templates = $items.map | $info | {
    {
      'contents'    => "{{ key \"${info['key']}\" }}",
      'destination' => "${puppetizer_main::ssl_path}/${info['name']}/${info['target']}.pem",
      'command'     => $cmd,
      'backup'      => false,
    }
  }

  $conf = {
    'consul'        => {
      'address' => $puppetizer_main::consul_addr,
      'token'   => $puppetizer_main::consul_token,
      # 'ssl'     => {
      #   'enabled' => false
      # },
    },
    'reload_signal' => 'SIGHUP',
    'kill_signal'   => 'SIGINT',
    'log_level'     => 'info',
    'template'      => $templates,
    # 'exec'          => {
    #   'command' => '',
    #   'reload_signal' => 'SIGHUP'
    # }
  }
  file { '/etc/consul-template.json':
    content => to_json_pretty($conf),
    notify  => Service['consul-template']
  }

  puppetizer::service { 'consul-template':
    start_content => @("END"/)
      #!/bin/sh -e
      cleanup(){
        kill -INT %1
        wait
        exit 0
      }
      trap '{ cleanup; }' TERM INT
      /usr/local/bin/consul-template -config /etc/consul-template.json &
      wait
      | END
    ,
    stop_content => "#!/bin/sh -e\nexec kill -SIGINT \$1",
    enabled => $puppetizer_main::consul_addr != undef
  }

  # Service['consul-template']
  # ->Service['nginx']

  # Service['consul-template']
  # ->Exec['puppetizer ssl seed']
}
