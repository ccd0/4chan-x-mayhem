Filter =
  init: ->
    return if !Conf['Filter']
    @loadFilters Conf['filters']
    Post.callbacks.push
      name: 'Filter'
      cb:   @node

    # XXX tmp conversion
    $.get 'filters', [], ({filters}) ->
      for source in ['comment', 'subject', 'name', 'tripcode', 'email', 'uniqueID', 'filename', 'MD5', 'dimensions', 'filesize', 'capcode', 'flag']
        <% if (type === 'crx') { %>
        $.localKeys.push source
        <% } %>
        Filter.convert filters, source
      return

  convert: (filters, source) ->
    $.get source, null, (items) ->
      return if items[source] is null
      filters.push Filter.convertText(items[source], source)...
      $.delete source
      $.set 'filters', filters
  convertText: (text, source) ->
    newItems = []
    for line in text.split '\n' when line[0] isnt '#'
      continue unless regexp = line.match /\/(.+)\/(\w*)/
      line = line.replace regexp[0], ''
      if source in ['uniqueID', 'MD5']
        type   = 'exact'
        filter = regexp[1]
      else
        type   = 'regexp'
        filter = "/#{regexp[1]}/#{regexp[2]}"
      item = {
        sources: [source]
        result: if /highlight/.test line then 'highlight' else 'hide'
        type: type
        filter: filter
      }
      item.post = switch line.match(/[^t]op:(yes|no|only)/)?[1] or 'yes'
        when 'no'
          ['reply']
        when 'only'
          ['op']
        else
          ['op', 'reply']
      if boards = line.match(/boards:([^;]+)/)?[1].toLowerCase()
        item.boards = boards.split(',').join ' '
      switch line.match(/stub:(yes|no)/)?[1]
        when 'yes'
          item.stubs = 'on'
        when 'no'
          item.stubs = 'off'
      if item.result is 'highlight'
        if klass = line.match(/highlight:(\w+)/)?[1]
          item.klass = klass
        if pin = line.match(/top:(yes|no)/)?[1] or 'yes'
          item.pin = 'off' if pin is 'no'
      newItems.push item
    newItems

  loadFilters: (items) ->
    newItems = []
    for item in items
      continue if item.disabled or !item.post.length or !item.sources.length
      continue if item.boards and g.BOARD.ID not in item.boards.split /\s+/

      switch item.type
        when 'partial'
          item.filter = item.filter.toLowerCase()
        when 'regexp'
          try
            m = item.filter.trim().match /^\/(.*)\/(\w*)$/
            item.filter = new RegExp m[1], m[2]
          catch err
            new Notice 'warning', "``#{item.filter}'' is an incorrect regular expression.", 15
            c.error err.stack
            continue

      item.test = Filter[item.type]
      delete item.type

      item.recurs = item.recurs is 'on' if item.recurs
      switch item.result
        when 'hide'
          item.stubs = item.stubs is 'on' if item.stubs
        when 'highlight'
          item.klass or= 'filter-highlight'
          item.pin    = item.pin isnt 'off'
          item.notify = item.notify is 'on'

      newItems.push item
    Filter.items = newItems

  node: ->
    return if @isClone
    matched = []
    for item in Filter.items
      continue unless @isReply and 'reply' in item.post or !@isReply and 'op' in item.post
      for source in item.sources when (value = Filter[source] @) isnt false
        continue unless item.test item.filter, value
        switch item.result
          when 'anti-hide'
            antiHide = true
          when 'anti-highlight'
            antiHighlight = true
          when 'anti-anonymize'
            antiAnonymize = true
          else
            matched.push item
    for item in matched
      switch item.result
        when 'hide'
          if !antiHide and (@isReply or g.VIEW is 'index')
            @hide "Hidden by filtering the #{source}: #{item.filter}", item.stubs, item.recurs
        when 'highlight'
          if !antiHighlight
            @highlight "Highlighted by filtering the #{source}: #{item.filter}", item.klass, item.pin, item.recurs
            Filter.openNotification @ if item.notify
        when 'anonymize'
          if !antiAnonymize
            Anonymize.node.call @
    return

  openNotification: (post, item) ->
    return unless Header.areNotificationsEnabled
    notif = new Notification ">>#{post} by #{post.getNameBlock()} got highlighted",
      body: post.info.comment
      icon: Favicon.logo
      tag:  post.fullID
    notif.onclick = ->
      Header.scrollToIfNeeded post.nodes.root, true
      window.focus()
    notif.onshow = ->
      setTimeout ->
        notif.close()
      , 7 * $.SECOND

  partial: (string, value) ->
    -1 isnt value.toLowerCase().indexOf string
  exact: (string, value) ->
    string is value
  regexp: (regexp, value) ->
    regexp.test value

  name: (post) ->
    if 'name' of post.info
      return post.info.name
    false
  uniqueID: (post) ->
    if 'uniqueID' of post.info
      return post.info.uniqueID
    false
  tripcode: (post) ->
    if 'tripcode' of post.info
      return post.info.tripcode
    false
  capcode: (post) ->
    if 'capcode' of post.info
      return post.info.capcode
    false
  email: (post) ->
    if 'email' of post.info
      return post.info.email
    false
  subject: (post) ->
    if 'subject' of post.info
      return post.info.subject or false
    false
  comment: (post) ->
    if 'comment' of post.info
      return post.info.comment
    false
  flag: (post) ->
    if 'flag' of post.info
      return post.info.flag
    false
  filename: (post) ->
    if post.file
      return post.file.name
    false
  dimensions: (post) ->
    {file} = post
    if file and (file.isImage or file.isVideo)
      return post.file.dimensions
    false
  filesize: (post) ->
    if post.file
      return post.file.size
    false
  MD5: (post) ->
    if post.file
      return post.file.MD5
    false

  menu:
    init: ->
      return if !Conf['Menu'] or !Conf['Filter']

      entry =
        el: $.el 'div', textContent: 'Filter'
        order: 50
        open: (post) ->
          Filter.menu.post = post
          true
        subEntries: []

      for type in [
        ['Name',             'name']
        ['Unique ID',        'uniqueID']
        ['Tripcode',         'tripcode']
        ['Capcode',          'capcode']
        ['E-mail',           'email']
        ['Subject',          'subject']
        ['Comment',          'comment']
        ['Flag',             'flag']
        ['Filename',         'filename']
        ['Image dimensions', 'dimensions']
        ['Filesize',         'filesize']
        ['Image MD5',        'MD5']
      ]
        # Add a sub entry for each filter type.
        entry.subEntries.push Filter.menu.createSubEntry type[0], type[1]

      Menu.menu.addEntry entry
    createSubEntry: (name, source) ->
      el = $.el 'a',
        href: 'javascript:;'
        textContent: name
      el.dataset.source = source
      $.on el, 'click', Filter.menu.makeFilter

      return {
        el: el
        open: Filter.menu.open
      }
    open: (post) ->
      false isnt Filter[@el.dataset.source] post
    makeFilter: ->
      Settings.open 'Filter'
      {source} = @dataset
      section  = $ '.section-filter'
      row      = Filter.makeRow $ 'template', section
      $('[name=sources]', row).value = source
      $('[name=type]',    row).value = 'exact'
      $('[name=filter]',  row).value = Filter[source](Filter.menu.post).replace /\n/g, '\\n'
      $('[name=save]',    row).disabled = false
      $.prepend $('.filter-items', section), row
      $('[name=filter]', row).focus()

  settings: (section) ->
    section.innerHTML = <%= importHTML('General/Settings-section-Filter') %>
    template  = $ 'template', section
    container = $ '.filter-items', section
    $.get 'filters', [], ({filters}) ->
      Filter.makeList section, filters
    $.on $('#new-filter-item', section), 'click', ->
      row = Filter.makeRow template
      $.prepend container, row
      $('[name=filter]', row).focus()
    $.on $('#save-filter-items', section), 'click', ->
      Filter.saveAllManually container
    $.on $('#export-filters', section), 'click', Filter.export
    $.on $('#import-filters', section), 'click', Filter.import
    $.on $('input[type=file]', section), 'change', Filter.onImport
  makeList: (section, filters) ->
    template = $ 'template', section
    rows = []
    for item in filters
      rows.push Filter.makeRow template, item
    $.add $('.filter-items', section), rows
  makeRow: (template, item) ->
    row     = d.importNode(template.content, true).firstChild
    # main
    post    = $ '[name=post]',    row
    enabled = $ '[name=enabled]', row
    result  = $ '[name=result]',  row
    sources = $ '[name=sources]', row
    type    = $ '[name=type]',    row
    filter  = $ '[name=filter]',  row
    # options
    boards  = $ '[name=boards]',  row
    recurs  = $ '[name=recurs]',  row
    stubs   = $ '[name=stubs]',   row
    klass   = $ '[name=klass]',   row
    pin     = $ '[name=pin]',     row
    notify  = $ '[name=notify]',  row

    if item
      row.dataset.data = JSON.stringify item
      $('[data-result]', row).dataset.result = item.result
      enabled.checked = !item.disabled
      for option in post.options
        option.selected = option.value in item.post
      for option in sources.options
        option.selected = option.value in item.sources
      for node in [result, type, boards, recurs, stubs, klass, pin, notify]
        node.value = item[node.name] if node.name of item
      filter.value = if item.type isnt 'regexp'
        item.filter.replace /\n/g, '\\n'
      else
        item.filter

    for node in [enabled, post, sources, result, type, filter, boards, recurs, stubs, klass, pin, notify]
      $.on node, 'change input', Filter.onRowChange
      $.on node, 'keydown', Filter.keydown
    for name in ['save', 'remove']
      $.on $("[name=#{name}]", row), 'click', Filter[name]

    row
  onRowChange: ->
    row = $.x 'ancestor::div[@class="filter-item"]', @
    $('[name=save]', row).disabled = row.dataset.data is Filter.getRowData row
    $('[data-result]', row).dataset.result = $('[name=result]', row).value
  keydown: (e) ->
    e.stopPropagation()
    return if e.keyCode isnt 13
    row = $.x 'ancestor::div[@class="filter-item"]', @
    $('[name=save]', row).click()
  getRowData: (row) ->
    item = {
      post: [$('[name=post]', row).options...]
        .filter (option) -> option.selected
        .map (option) -> option.value
      sources: [$('[name=sources]', row).options...]
        .filter (option) -> option.selected
        .map (option) -> option.value
      result: $('[name=result]', row).value
      type:   $('[name=type]',   row).value
      filter: $('[name=filter]', row).value
    }
    if item.type isnt 'regexp'
      item.filter = item.filter.replace /\\n/g, '\n'
    if boards = $('[name=boards]', row).value.trim().toLowerCase()
      item.boards = boards
    switch item.result
      when 'hide'
        item.recurs = recurs if recurs = $('[name=recurs]', row).value
        item.stubs  = stubs  if stubs  = $('[name=stubs]',  row).value
      when 'highlight'
        item.recurs = recurs if recurs = $('[name=recurs]', row).value
        item.klass  = klass  if klass  = $('[name=klass]',  row).value.trim()
        item.pin    = pin    if pin    = $('[name=pin]',    row).value
        item.notify = notify if notify = $('[name=notify]', row).value
    item.disabled = true unless $('[name=enabled]', row).checked
    JSON.stringify item
  save: ->
    row = $.x 'ancestor::div[@class="filter-item"]', @
    row.dataset.data = Filter.getRowData row
    Filter.saveAll row.parentNode
    @disabled = true
  remove: ->
    row  = $.x 'ancestor::div[@class="filter-item"]', @
    list = row.parentNode
    $.rm row
    Filter.saveAll list
  saveAllManually: (list) ->
    for row in list.children when !(save = $ '[name=save]', row).disabled
      row.dataset.data = Filter.getRowData row
      save.disabled = true
    Filter.saveAll list
  saveAll: (list) ->
    items = [list.children...]
      .map (row) -> row.dataset.data
      .filter (data) -> data # new, unsaved rows
      .map (data) -> JSON.parse data
    $.set 'filters', items
    Filter.loadFilters items
  export: ->
    $.get 'filters', [], ({filters}) ->
      Settings.downloadExport 'Filters', {version: g.VERSION, date: Date.now(), filters}
  import: ->
    $('input[type=file]', @parentNode).click()
  onImport: ->
    return unless file = @files[0]
    reader  = new FileReader()
    section = $.x 'ancestor::section', @
    reader.onload = (e) ->
      try
        newFilters = JSON.parse(e.target.result).filters
      catch err
        alert 'Import failed due to an error.'
        c.error err.stack
        return
      {length} = newFilters
      return unless confirm "You are about to add #{length} new filter#{if length is 1 then '' else 's'}, are you sure?"
      $.get 'filters', [], ({filters}) ->
        filters.push newFilters...
        $.set 'filters', filters
        Filter.makeList section, filters
        Filter.loadFilters filters
    reader.readAsText file
