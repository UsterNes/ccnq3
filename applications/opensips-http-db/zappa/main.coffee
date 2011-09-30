#!/usr/bin/env coffee
###
(c) 2010 Stephane Alnet
Released under the AGPL3 license
###

require('ccnq3_config').get (config)->

  zappa = require 'zappa'
  zappa config.opensips_proxy.port, config.opensips_proxy.hostname, {config}, ->

    cdb = require 'cdb'
    db = cdb.new config.provisioning.couchdb_uri

    loc_db = cdb.new config.opensips_proxy.usrloc_uri

    # db_dbase.c lists: int, double, string, str, blob, date; str and blob are equivalent for this interface.
    column_types =
      usrloc:
        username: 'string'
        domain: 'string'
        contact: 'string'
        received: 'string'
        path: 'string'
        expires: 'date'
        q: 'double'
        callid: 'string'
        cseq: 'int'
        last_modified: 'date'
        flags: 'int'
        cflags: 'int'
        user_agent: 'string'
        socket: 'string'
        methods: 'int'
      version:
        table_name: 'string'
        table_version: 'int'
      dr_gateways:
        gwid: 'int'
        type: 'int'
        address: 'string'
        strip: 'int'
        pri_prefix: 'string'
        attrs: 'string'
        probe_mode: 'int'
        description: 'string'
      dr_rules:
        ruleid: 'int'
        # keys
        groupid: 'string'
        prefix: 'string'
        priority: 'int'
        # others
        timerec: 'string'
        routeid: 'string'
        gwlist: 'string'
        attrs: 'string'
        description: 'string'
      dr_gw_lists:
        id:'int'
        gwlist:'string'
      dr_groups:
        username:'string'
        domain:'string'
        groupid:'int'
      domain:
        domain: 'string'
      subscriber:
        username: 'string'
        domain: 'string'
        password: 'string'
        ha1: 'string'
        ha1b: 'string'
        rpid: 'string'
      avpops:
        uuid: 'string'
        username: 'string'
        domain: 'string'
        attribute: 'string'
        type: 'int'
        value: 'string'
      location:
        username:'string'
        domain:'string'
        contact:'string'
        received:'string'
        path:'string'
        expires:'date'
        q:'double'
        callid:'string'
        cseq:'int'
        last_modified:'date'
        flags:'int'
        cflags:'int'
        user_agent:'string'
        socket:'string'
        methods:'int'


    @use 'bodyParser', 'logger'

    quoted_value = (t,x) ->
      # No value: no quoting.
      if not x?
        return ''

      # Expects numerical types => no quoting.
      if t is 'int' or t is 'double'
        # assert(parseInt(x).toString is x) if t is 'int' and typeof x isnt 'number'
        # assert(parseFloat(x).toString is x) if t is 'double' and typeof x isnt 'number'
        return x

      # assert(t is 'string')
      if typeof x is 'number'
        x = x.toString()
      if typeof x isnt 'string'
        x = JSON.stringify x
      # assert typeof x is 'string'

      # Assumes quote_delimiter = '"'
      return '"'+x.replace(/"/g, '""')+'"'


    field_delimiter = "\t"
    row_delimiter = "\n"

    line = (a) ->
      a.join(field_delimiter) + row_delimiter

    first_line = (types,c)->
      return line( types[col] for col in c.split ',' )

    value_line = (types,hash,c)->
      return line( quoted_value(types[col], hash[col]) for col in c.split ',' )

    @helper from_array: (n,t,c) ->
      if not t? or t.length is 0 then return @send ""
      types = column_types[n]
      @send first_line(types,c) + ( value_line(types,l,c) for l in t ).join('')

    @helper from_hash: (n,h,c) ->
      if not h? then return @send ""
      types = column_types[n]
      @send first_line(types,c) + value_line(types,h,c)

    unquote_value = (t,x) ->

      if not x?
        return x

      if t is 'int'
        return parseInt(x)
      if t is 'double'
        return parseFloat(x)
      # Not sure what the issue is, but we're getting garbage at the end of dates.
      if t is 'date'
        d = new Date(x)
        # Format expected by db_str2time() in db/db_ut.c
        # TODO: This requires opensips to be started in UTC, assuming
        #       toISOString() outputs using UTC (which it does in Node.js 0.4.11).
        return d.toISOString().replace 'T', ' '

      # string, blob, ...
      return x.toString()

    unquote_params = (k,v,table)->
      doc = {}
      names = k.split ','
      values = v.split ','
      types = column_types[table]

      doc[names[i]] = unquote_value(types[names[i]],values[i]) for i in [0..names.length]

      return doc

    # Action!
    @get '/domain/': ->
      if @query.k is 'domain'
        db.get "domain:#{@query.v}", (t) =>
          if t.error then return send ""
          from_hash 'domain', t, @query.c
        return

      throw 'not handled'

    @get '/subscriber/': -> # auth_table
      if @query.k is 'username,domain'
        # Parse @v -- what is the actual format?
        [username,domain] = @query.v.split ","
        db.get "endpoint:#{username}@#{domain}", (t) =>
          if t.error then return send ""
          from_hash 'subscriber', t, @query.c
        return

      throw 'not handled'

    @get '/location/': -> # usrloc_table

      if @query.k is 'username'
        loc_db.get @query.v, (p) =>
          if p.error then return send ""
          from_hash 'usrloc', p, @query.c
        return

      if not @query.k?
        # Rewrite-me: will load everything in memory and build the reply in memory.
        # Instead use a CouchDB "list"
        #   loc_db.req "_design/http_db/_list/usrloc/_all_docs"
        # and figure out how to stream the response through Zappa.
        loc_db.req {uri:'_all_docs?include_docs=true'}, (t) =>
          from_array 'usrloc', (u.doc for u in t.rows), @query.c
        return

      throw 'not handled'

    @post '/location': ->

      doc = unquote_params(@body.k,@body.v,'location')
      # Note: this allows for easy retrieval, but only one location can be stored.
      # Use "callid" as an extra key parameter otherwise.
      doc._id = "#{doc.username}@#{doc.domain}"

      if @body.query_type is 'insert' or @body.query_type is 'update'

        loc_db.head doc._id, (p) =>
          doc._rev = p._rev if p._rev?
          loc_db.put doc, (r) =>
            if r.error then return send ""
            send r._id
        return

      if @query_type is 'delete'

        loc_db.head doc._id, (p) =>
          if not p._rev? then return send ""
          doc._rev = p._rev
          loc_db.del doc, (p) =>
            if p.error then return send ""
            send ""
        return

      throw 'not handled'

    @get '/avpops/': ->

      if @query.k is 'uuid,attribute'
        [uuid,attribute] = @query.v.split ','
        db.get "#{attribute}:#{uuid}", (p) =>
          if p.error then return send ""
          avp =
            value: p
            attribute: attribute
            type: 2
          from_hash 'avpops', avp, @query.c
        return

      if @query.k is 'username,domain,attribute'
        [username,domain,attribute] = @query.v.split ','
        db.get "#{attribute}:#{username}@#{domain}", (p) =>
          if p.error then return send ""
          avp =
            value: p
            attribute: attribute
            type: 2
          from_hash 'avpops', avp, @query.c
        return

      throw 'not handled'


    @get '/dr_gateways/': ->
      if not @query.k?
        db.req {uri:"#{config._id}/dr_gateways.json"}, (t) =>
          if t.error? then return send ""
          from_array 'dr_gateways', t, @query.c
        return
      ###
      my %attrs = ();
      $attrs{realm}    = $uac_realm if defined($uac_realm) && $uac_realm ne '';
      $attrs{user}     = $uac_user  if defined($uac_user ) && $uac_user  ne '';
      $attrs{pass}     = $uac_pass  if defined($uac_pass ) && $uac_pass  ne '';
      $attrs{force_mp} = $force_mp  if defined($force_mp ) && $force_mp  ne '';

      my $attrs = join(';', map { "$_=$attrs{$_}" } keys(%attrs) );
      ###

      throw 'not handled'

    @get '/dr_rules/': -> # ?c=ruleid,groupid,prefix,timerec,priority,routeid,gwlist,attrs
      if not @query.k?
        db.req {uri:"#{config._id}/dr_rules.json"}, (t) =>
          if t.error? then return send ""
          from_array 'dr_rules', t, @query.c
        return

      throw 'not handled'

    @get '/dr_groups/': ->

      if @query.k is 'username,domain'
        [username,domain] = @query.v.split ','
        # However we do not currently support "number@domain", so skip that.
        db.get "number/#{username}", (t) =>
          if t.error? then return send ""
          from_hash 'dr_groups', t, @query.c
        return

      throw 'not handled'

    @get '/dr_gw_lists/': -> # id,gwlist
      if not @query.k?
        db.req {uri:"#{config._id}/dr_gw_lists.json"}, (t) =>
          if t.error? then return send ""
          from_array 'dr_gw_lists', t, @query.c
        return

      throw 'not handled'

    @get '/version/': ->
      if @query.k is 'table_name' and @query.c is 'table_version'

        # Versions for OpenSIPS 1.7.0
        versions =
          location: 1006
          subscriber: 7
          dr_gateways: 4
          dr_rules: 3

        return from_hash 'version', {table_version:versions[@query.v]}, @query.c

      throw 'not handled'
