#!/usr/bin/env coffee
# (c) 2012 Stephane Alnet

# See
#   http://wiki.freeswitch.org/wiki/Mod_enum
# for FreeSwitch usage.

Zone = require('./dns').Zone

cdb = require 'cdb'

make_id = (t,n) -> [t,n].join ':'

# Options should contain provisioning_uri
#  provisioning_uri = config.provisioning.local_couchdb_uri

exports.EnumZone = class EnumZone extends Zone

  constructor: (domain, @provisioning_uri, options) ->
    super domain, options

  select: (type,name,cb) ->
    unless type is 'NAPTR' and number = name.match(/^([\d.]+)\./)?[1]
      return super type, name, cb

    number = number.split('.').reverse().join('')

    provisioning = cdb.new @provisioning_uri
    provisioning.get make_id('number',number), (r) =>
      if r.inbound_uri?
        cb [
          @create_record
            name:name
            ttl: @ttl
            class: "NAPTR"
            value: [10,100,'u','E2U+sip',"!^.*$!#{r.inbound_uri}!", ""]
          @create_record
            name:name
            ttl: @ttl
            class: "NAPTR"
            value: [20,100,'u','E2U+account', "!^.*$!#{r.account}!", ""]
        ]
        # In FreeSwitch XML, retrieve the account from enum_route_2.
      else
        cb()

  # The regular "handles" should work but is recursive and could be slow for ENUM.
  handles: (domain) ->
    domain = @dotize(domain)
    if domain is @dot_domain
      return true
    if domain.match(/^[\d.]+\.(.*)+$/)?[1] is @dot_domain
      return true
    false
