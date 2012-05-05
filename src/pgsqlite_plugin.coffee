# Copyright (C) 2011 Joe Noon <joenoon@gmail.com>

# This file is intended to be compiled by Coffeescript WITH the top-level function wrapper

root = this

callbacks = {}

counter = 0

cbref = (hash) ->
  f = "cb#{counter+=1}"
  callbacks[f] = hash
  f

getOptions = (opts, success, error) ->
  cb = {}
  has_cbs = false
  if typeof success == "function"
    has_cbs = true
    cb.success = success
  if typeof error == "function"
    has_cbs = true
    cb.error = error
  opts.callback = cbref(cb) if has_cbs
  opts
  
class root.PGSQLitePlugin
  
  # All instances will interact directly on the prototype openDBs object.
  # One instance that closes a db path will remove it from any other instance's perspective as well.
  openDBs: {}
  
  constructor: (@dbPath, @openSuccess, @openError) ->
    throw new Error "Cannot create a PGSQLitePlugin instance without a dbPath" unless dbPath
    @openSuccess ||= () ->
      console.log "DB opened: #{dbPath}"
      return
    @openError ||= (e) ->
      console.log e.message
      return
    @open(@openSuccess, @openError)
  
  # Note: Class method
  @handleCallback: (ref, type, obj) ->
    callbacks[ref]?[type]?(obj)
    callbacks[ref] = null
    delete callbacks[ref]
    return
  
  @openDatabase: (dbPath, version, ignored, maxSize, success, error) ->
    db = new root.PGSQLitePlugin dbPath, success, error
    return db
    
  executeSql: (sql, success, error) ->
    throw new Error "Cannot executeSql without a query" unless sql
    opts = getOptions({ query: [].concat(sql || []), path: @dbPath }, success, error)
    Cordova.exec("PGSQLitePlugin.backgroundExecuteSql", opts)
    return

  transaction: (fn, error, success) ->
    t = new root.PGSQLitePluginTransaction(@dbPath)
    fn(t)
    t.complete(success, error)
    
  open: (success, error) ->
    unless @dbPath of @openDBs
      @openDBs[@dbPath] = true
      db = @
      onSuccess = -> success db
      opts = getOptions({ path: @dbPath }, onSuccess, error)
      Cordova.exec("PGSQLitePlugin.open", opts)
    return
  
  close: (success, error) ->
    if @dbPath of @openDBs
      delete @openDBs[@dbPath]
      opts = getOptions({ path: @dbPath }, success, error)
      Cordova.exec("PGSQLitePlugin.close", opts)
    return

class root.PGSQLitePluginTransaction
  
  constructor: (@dbPath) ->
    @executes = []
    
  executeSql: (sql, success, error) ->
    if typeof success != 'function' # html5-like interface
      sql = arguments[0]
      values = arguments[1]
      success = arguments[2]
      error = arguments[3]
      sql = [sql].concat(values)

    success = success || ->
    error = error || ->
    tx = @
    onSuccess = (res) -> success tx, res

    @executes.push getOptions({ query: [].concat(sql || []), path: @dbPath }, onSuccess, error)
    return
  
  complete: (success, error) ->
    throw new Error "Transaction already run" if @__completed
    @__completed = true
    begin_opts = getOptions({ query: [ "BEGIN;" ], path: @dbPath })
    commit_opts = getOptions({ query: [ "COMMIT;" ], path: @dbPath }, success, error)
    executes = [ begin_opts ].concat(@executes).concat([ commit_opts ])
    opts = { executes: executes }
    Cordova.exec("PGSQLitePlugin.backgroundExecuteSqlBatch", opts)
    @executes = []
    return

