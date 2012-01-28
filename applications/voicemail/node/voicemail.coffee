#!/usr/bin/env coffee
###
(c) 2010 Stephane Alnet
Released under the AGPL3 license
###

###
  This is the ccnq3 ESL voicemail server.

  This script accepts an incoming call,
  creates a FIFO for bi-directional audio,
  and proceeds with redirecting the call.

  FIFO relays are created as needed to record or play
  files to/from remote CouchDB. (This avoids having to download
  audio prompts, or store then upload recorded messages.)

  Voicemail content is stored as .wav PCM mono 16 bits (generated
  by FreeSwitch) which can then be transcoded.
  (RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 8000 Hz)

  The authentication is done using our standard CouchDB access.

  Individual voicemail accounts (for example phone-number@domain) are registered
  as CouchDB users, and given access to a userDB.
  (A priori that userDB might be the same as some existing web-based user's,
  allowing for web voicemail, etc.).
  [In other words a given "userDB" can be shared by multiple user accounts.]

  The password for these voicemail accounts is the voicemail PIN.

  (Retrieval of voicemail messages from a TV-box might be done similarly by
  authenticating the box and giving it access to a userDB.)

  For leaving (inbound) voicemails, "system" accounts (for example 
  voicemail@host or @domain) are used which can create and update
  "voicemail" type records in the target's user database.
  (They also need to be able to read user accounts so that they know
  what the URI for a given userDB is.)

  The receiving user record (a priori the voicemail account's) must contain:

    notification.email  (mailto URI)
    notification.wmi    (SIP URI)

  Attachments:

    name.wav      WAV 16 bits (8kHz or higher)
    prompt.wav    WAV 16 bits (8kHz or higher)

###

esl = require 'esl'
util = require 'util'
querystring = require 'querystring'
cdb = require 'cdb'

###
  The call is managed by a regular XML application.
  This code simply creates a FIFO for recording since mod_httapi means we can play directly from the server.
###

require('ccnq3_config').get (config)->

  # esl.debug = true

  server = new esl.CallServer()

  server.on 'CONNECT', (req,res) ->

    vm_box     = req.channel_data.variable_vmbox

    util.log "Answering call for #{vm_box}"
    res.execute 'answer', (req,res) ->
      util.log "Call answered"

  server.listen(config.voicemail.public_port)
