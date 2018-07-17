# Configuration options for the tlog-rec-session.conf
type Tlog::RecSessionConf = Struct[{
  Optional['shell']    => Stdlib::Absolutepath,
  Optional['notice']   => String,
  Optional['writer']   => Enum['journal', 'syslog', 'file'],
  Optional['latency']  => Integer[1],
  Optional['payload']  => Integer[1],
  Optional['log'] => Struct[{
    Optional['input']  => Boolean,
    Optional['output'] => Boolean,
    Optional['window'] => Boolean
  }],
  Optional['limit'] => Struct[{
    Optional['rate']   => Integer[1],
    Optional['burst']  => Integer[1],
    Optional['action'] => Enum['pass','delay','drop']
  }],
  Optional['file'] => Struct[{
    'path' => Stdlib::Absolutepath
  }],
  Optional['syslog'] => Struct[{
    Optional['facility'] => Simplib::Syslog::LowerFacility,
    Optional['priority'] => Simplib::Syslog::LowerSeverity
  }],
  Optional['journal'] => Struct[{
    Optional['priority'] => Simplib::Syslog::LowerSeverity,
    Optional['augment']  => Boolean
  }]
}]
