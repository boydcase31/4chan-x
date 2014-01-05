Unread =
  init: ->
    return if g.VIEW isnt 'thread' or !Conf['Unread Count'] and !Conf['Unread Favicon'] and !Conf['Desktop Notifications']

    @db = new DataBoard 'lastReadPosts', @sync
    @hr = $.el 'hr',
      id: 'unread-line'
    @posts = new RandomAccessList
    @postsQuotingYou = []

    Thread.callbacks.push
      name: 'Unread'
      cb:   @node

  node: ->
    Unread.thread = @
    Unread.title  = d.title
    Unread.lastReadPost = Unread.db.get
      boardID: @board.ID
      threadID: @ID
      defaultValue: 0
    $.on d, '4chanXInitFinished',      Unread.ready
    $.on d, 'ThreadUpdate',            Unread.onUpdate
    $.on d, 'scroll visibilitychange', Unread.read
    $.on d, 'visibilitychange',        Unread.setLine if Conf['Unread Line']

  ready: ->
    $.off d, '4chanXInitFinished', Unread.ready
    posts = []
    for ID, post of Unread.thread.posts
      posts.push post if post.isReply
    Unread.addPosts posts
    Unread.scroll()

  scroll: ->
    return unless Conf['Scroll to Last Read Post']
    # Let the header's onload callback handle it.
    return if (hash = location.hash.match /\d+/) and hash[0] of Unread.thread.posts
    if post = Unread.posts.first
      # Scroll to a non-hidden, non-OP post that's before the first unread post.
      while root = $.x 'preceding-sibling::div[contains(@class,"replyContainer")][1]', post.nodes.root
        break unless (post = Get.postFromRoot root).isHidden
      return unless root
      down = true
    else
      # Scroll to the last read post.
      posts  = Object.keys Unread.thread.posts
      {root} = Unread.thread.posts[posts[posts.length - 1]].nodes
    
    # Scroll to the target unless we scrolled past it.
    Header.scrollTo root, down if Header.getBottomOf(root) < 0

  sync: ->
    lastReadPost = Unread.db.get
      boardID: Unread.thread.board.ID
      threadID: Unread.thread.ID
      defaultValue: 0
    return unless Unread.lastReadPost < lastReadPost
    Unread.lastReadPost = lastReadPost
    Unread.readArray Unread.posts

    post = Unread.posts.first
    while post
      break if post.ID > Unread.lastReadPost
      post = post.next
    Unread.posts.splice 0, i
    
    Unread.readArray Unread.postsQuotingYou
    Unread.setLine() if Conf['Unread Line']
    Unread.update()

  addPosts: (posts) ->
    for post in posts
      {ID} = post
      if ID <= Unread.lastReadPost or post.isHidden
        continue
      if QR.db
        data =
          boardID:  post.board.ID
          threadID: post.thread.ID
          postID:   post.ID
        continue if QR.db.get data
      Unread.posts.push post
      Unread.addPostQuotingYou post
    if Conf['Unread Line']
      # Force line on visible threads if there were no unread posts previously.
      Unread.setLine Unread.posts[0] in posts
    Unread.read()
    Unread.update()

  addPostQuotingYou: (post) ->
    return unless QR.db
    for quotelink in post.nodes.quotelinks when QR.db.get Get.postDataFromLink quotelink
      Unread.postsQuotingYou.push post
      Unread.openNotification post
      return

  openNotification: (post) ->
    return unless Header.areNotificationsEnabled
    name = if Conf['Anonymize']
      'Anonymous'
    else
      $('.nameBlock', post.nodes.info).textContent.trim()
    notif = new Notification "#{name} replied to you",
      body: post.info.comment
      icon: Favicon.logo
    notif.onclick = ->
      Header.scrollToIfNeeded post.nodes.root, true
      window.focus()
    notif.onshow = ->
      setTimeout ->
        notif.close()
      , 7 * $.SECOND

  onUpdate: (e) ->
    if e.detail[404]
      Unread.update()
    else
      Unread.addPosts e.detail.newPosts

  readSinglePost: (post) ->
    {ID} = post
    return unless Unread.posts[ID]
    Unread.posts.splice ID post.next.ID
    if post is Unread.posts.first
      Unread.lastReadPost = post.ID
      Unread.saveLastReadPost()
    if (i = Unread.postsQuotingYou.indexOf post) isnt -1
      Unread.postsQuotingYou.splice i, 1
    Unread.update()

  readArray: (arr) ->
    for post, i in arr
      break if post.ID > Unread.lastReadPost
    arr.splice 0, i

  read: $.debounce 50, (e) ->
    return if d.hidden or !Unread.posts.length
    height  = doc.clientHeight
    {posts} = Unread

    post = posts.first

    while post
      if Header.getBottomOf(post.nodes.root) > -1 # post is not completely read
        {ID} = post
        if Conf['Mark Quotes of You']
          if post.info.yours
            QuoteYou.lastRead = post.nodes.root
        post = post.next
      else
        break

    return unless ID

    posts.splice 0, ID
    Unread.lastReadPost = ID if Unread.lastReadPost < ID or !Unread.lastReadPost
    Unread.saveLastReadPost()
    Unread.readArray Unread.postsQuotingYou
    Unread.update() if e

  saveLastReadPost: $.debounce 2 * $.SECOND, ->
    return if Unread.thread.isDead
    Unread.db.set
      boardID: Unread.thread.board.ID
      threadID: Unread.thread.ID
      val:      Unread.lastReadPost

  setLine: (force) ->
    return unless d.hidden or force is true
    return $.rm Unread.hr unless post = Unread.posts[0]
    if $.x 'preceding-sibling::div[contains(@class,"replyContainer")]', post.nodes.root # not the first reply
      $.before post.nodes.root, Unread.hr

  update: <% if (type === 'crx') { %>(dontrepeat) <% } %>->
    count = Unread.posts.length

    if Conf['Unread Count']
      d.title = "#{if Conf['Quoted Title'] and Unread.postsQuotingYou.length then '(!) ' else ''}#{if count or !Conf['Hide Unread Count at (0)'] then "(#{count}) " else ''}#{if g.DEAD then "/#{g.BOARD}/ - 404" else "#{Unread.title}"}" 
      <% if (type === 'crx') { %>
      # XXX Chrome bug where it doesn't always update the tab title.
      # crbug.com/124381
      # Call it one second later,
      # but don't display outdated unread count.
      return if dontrepeat
      setTimeout ->
        d.title = ''
        Unread.update true
      , $.SECOND
      <% } %>

    return unless Conf['Unread Favicon']

    Favicon.el.href =
      if g.DEAD
        if Unread.postsQuotingYou[0]
          Favicon.unreadDeadY
        else if count
          Favicon.unreadDead
        else
          Favicon.dead
      else
        if count
          if Unread.postsQuotingYou[0]
            Favicon.unreadY
          else
            Favicon.unread
        else
          Favicon.default

    <% if (type === 'userscript') { %>
    # `favicon.href = href` doesn't work on Firefox.
    $.add d.head, Favicon.el
    <% } %>
