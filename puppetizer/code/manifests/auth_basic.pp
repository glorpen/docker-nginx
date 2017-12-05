define puppetizer_main::auth_basic(
  Hash $users = {}
){
  include ::puppetizer_main
  
  file { "${::puppetizer_main::auth_dir}/${name}.passwd":
    ensure => present,
    content => $users.reduce("") | $memo, $v | {
      "${memo}${v[0]}:${v[1]}\n"
    },
    require => File[$::puppetizer_main::auth_dir],
  }
}
