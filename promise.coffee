class SPromise

  _ref = null

  # () -> SPromise
  @apply: -> new SPromise()

  # (A) -> SPromise[A]
  @successful: (result) -> SPromise.apply().success(result)

  # (String) -> SPromise
  @failed: (err) -> SPromise.apply().failure(err)

  # () -> SFuture[A]
  future: ->
    _ref = new SFuture() if (_ref is null)

    _ref

  # () -> Boolean
  isCompleted: -> _ref != null && _ref.isCompleted()

  # Complete current Future with result from another Future
  #
  # (SFuture[A]) -> Unit
  join: (otherFuture) ->
    otherFuture.onComplete(
      (s) => @success(s)
      (e) => @failure(e)
    )

    return

  success: (value) ->
    @future().setState(value)

    return

  failure: (cause) ->
    @future().setState(cause, false)

    return

class SFuture
  _handlers =
    s: []
    f: []

  _stateSet = 0
  _state = null

  # Executes passed code (pseudo-)asynchronously, returning future, containing result of passed func
  #
  # (() -> A) -> SFuture[A]
  @apply: (func, timeout = 0) ->
    p = SPromise.apply()
    f = ->
      try
        p.success(func())
      catch error
        p.failure(error)

      return

    setTimeout(f, timeout)

    p.future()

  # (String) -> SFuture
  @failed: (err) -> SPromise.failed(err).future()

  # (A) -> SFuture[A]
  @successful: (result) -> SPromise.successful(result).future()

  # Returns future with values form all futures, which completes when all underlying futures are completed
  #
  # (Array[Future[A]]) -> Future[Array[A]]
  @sequence: (futures) ->
    result = SFuture.successful([])

    for f in futures
      result = result.flatMap((r) -> f.map((v) -> r.push(v)))

    result

  # Returns future with value of first completed future
  #
  # (Array[Future[A]]) -> Future[A]
  @firstCompletedOf: (futures) ->
    p = SPromise.apply()

    p.join(f) for f in futures

    p.future()

  # (A, Boolean) -> Unit
  setState: (s, succ = yes) ->
    # Ignore new state if future already completed
    if @isCompleted() then return

    _state = s
    _stateSet = if succ then 1 else -1

    h(s) for h in (if succ then _handlers.s else _handlers.f)

    _handlers = null # Remove links to handlers

    return

  # (A -> Unit) -> Unit
  onSuccess: (cb) ->
    if (@isCompleted()) then cb(_state) if (@isSuccessful())
    else _handlers.s.push(cb)

    return

  # (String -> Unit) -> Unit
  onFailure: (cb) ->
    if (@isCompleted()) then cb(_state) unless (@isSuccessful())
    else _handlers.f.push(cb)

    return

  # (A -> Unit, String -> Unit) -> Unit
  onComplete: (success, failure) ->
    @onSuccess(success)
    @onFailure(failure)

    return

  # () -> Boolean
  isCompleted: -> _stateSet != 0

  # () -> Boolean
  isSuccessful: ->
    unless @isCompleted() then throw "Calling isSuccessful on incomplete SFuture is not allowed"
    else _stateSet > 0

  # (A -> B) -> SFuture[B]
  map: (mapper) ->
    p = SPromise.apply()

    @onComplete(
      (s) ->
        try
          p.success(mapper(s))
        catch error
          p.failure(error)
      (e) -> p.failure(e)
    )

    p.future()

  # (A -> SFuture[B]) -> SFuture[B]
  flatMap: (flatMapper) ->
    p = SPromise.apply()

    @onComplete(
      (s) ->
        try
          p.join(flatMapper(s))
        catch error
          p.failure(error)
      (e) -> p.failure(e)
    )

    p.future()

  # (A -> Boolean) -> SFuture[A]
  filter: (filter) ->
    p = SPromise.apply()

    if (filter(s)) p.success(s)
    else p.failure("SFuture.filter predicate is not satisfied")

    p.future()

  # Zip `this` and `that` SFuture, resulting new SFuture, contained an array with results of two SFutures
  #
  # (SFuture[B]) -> SFuture[(A, B)]
  zip: (that) ->
    p = SPromise.apply()

    @onComplete(
      (s) -> that.onComplete(
        (thatS) -> p.success([s, thatS])
        (e) -> p.failure(e)
      )
      (e) -> p.failure(e)
    )

  # (SFuture[A]) -> SFuture[A]
  fallbackTo: (that) ->
    p = SPromise.apply()

    @onComplete(
      (s) -> p.success s
      (e) -> that.onComplete(
        (thatS) -> p.success thatS
        () -> p.failure e # Use the first failure as the failure
      )
    )

    p.future()

  # Same as onComplete, but used for chaining side-effecting operations with normal operations
  #
  # (A -> Unit, String -> Unit) -> SFuture[A]
  andThen: (succes, failure) ->
    p = SPromise.apply()

    @onComplete(
      (s) -> succes(s); p.success(s)
      (e) -> failure(e); p.failure(e)
    )

    p.future()

