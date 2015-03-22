## Utility functions

# Handlers just pass values to promise, working as side-effecting identity function
passSuccessToPromise = (p) -> (s) -> p.success(s)
passFailureToPromise = (p) -> (e) -> p.failure(e)

# Create new promise, call a function passing a promise, and return a future from this promise
# Used in most mutating operations.
#
# ((SPromise[A]) -> Unit) -> SFuture[A]
newPromise = (f) ->
  p = new SPromise()
  f(p)

  p.future()

# Try/catch pattern, close promise with the result of a function or an error
#
# (SPromise[A], () -> A) -> Unit
tryCompletingPromise = (p, f) ->
  val = null
  error = null
  success = no

  try
    val = if isFunction(f) then f() else f
    success = yes
  catch error
  finally
    if success then p.success(val)
    else p.failure(error)

  return

isFunction = (a) -> typeof a is "function"

## Main classes

class SPromise

  ## Static methods ##

  # (A) -> SPromise[A]
  @successful: (result) ->
    p = new SPromise()
    p.success(result)
    p

  # (String) -> SPromise
  @failed: (err) ->
    p = new SPromise()
    p.failure(err)
    p

  ## End of static methods ##

  constructor: ->
    @_ref = null

  # () -> SFuture[A]
  future: ->
    @_ref = new SFuture() if @_ref is null

    @_ref

  # () -> Boolean
  isCompleted: -> @_ref != null && @_ref.isCompleted()

  # Complete current Future with result from another Future
  #
  # (SFuture[A]) -> Unit
  join: (otherFuture) ->
    otherFuture.onComplete(passSuccessToPromise(@), passFailureToPromise(@))

    return

  success: (value) ->
    @future().setState(value)

    return

  failure: (cause) ->
    @future().setState(cause, false)

    return


class SFuture

  ## Static methods ##

  # Executes passed code (pseudo-)asynchronously, returning future, containing result of passed func
  #
  # (() -> A, Int) -> SFuture[A]
  @apply: (func, timeout = 0) -> newPromise (p) ->
    delayedF = ->
      tryCompletingPromise(p, func)

      return

    setTimeout(delayedF, timeout)

    return

  # (String) -> SFuture
  @failed: (err) -> SPromise.failed(err).future()

  # (A) -> SFuture[A]
  @successful: (result) -> SPromise.successful(result).future()

  # Returns future with values form all futures, which completes when all underlying futures are completed
  #
  # (Array[Future[A]]) -> Future[Array[A]]
  @sequence: (futures) ->
    result = SFuture.successful([])
    futures.forEach((future) ->
      result = result.flatMap((r) -> future.map((v) -> r.push(v); r))

      return
    )

    result

  # Used to apply a function to all items of a list in parallel, returning a future with array of resulting items
  #
  # (Array[A], A -> Future[B]) -> Future[Array[B]]
  @traverse: (list, fn) ->
    result = SFuture.successful([])
    list.forEach((item) ->
      fb = fn(item)
      result = result.flatMap((items) -> fb.map((res) -> items.push(res); items))

      return
    )

    result

  # Returns future with value of first completed future
  #
  # (Array[Future[A]]) -> Future[A]
  @firstCompletedOf: (futures) -> newPromise((p) ->
    p.join(f) for f in futures

    return
  )

  ## End of static methods ##

  constructor: ->
    @_handlers = { s: [], f: [] }
    @_stateSet = 0
    @_state = null

  # (A, Boolean) -> Unit
  setState: (s, succ = yes) ->
    # Ignore new state if a future is already completed
    if @isCompleted() then return

    @_state = s
    @_stateSet = if succ then 1 else -1

    exceptions = []

    for h in (if succ then @_handlers.s else @_handlers.f)
      if isFunction(h)
        try h(s)
        catch exc
          exceptions.push(exc)

    @_handlers = null # Remove links to handlers

    if exceptions.length > 0 then throw "Exceptions thrown while executing callbacks: " + exceptions.join(", ")

    return

  # (A -> Unit) -> Unit
  onSuccess: (cb) ->
    if @isCompleted() then cb(@_state) if @isSuccessful()
    else @_handlers.s.push(cb)

    return

  # (String -> Unit) -> Unit
  onFailure: (cb) ->
    if @isCompleted() then unless @isSuccessful() then cb(@_state)
    else @_handlers.f.push(cb)

    return

  # (A -> Unit, String -> Unit) -> Unit
  onComplete: (success, failure) ->
    @onSuccess(success)
    @onFailure(failure)

    return

  # () -> Boolean
  isCompleted: -> @_stateSet != 0

  # () -> Boolean
  isSuccessful: ->
    unless @isCompleted() then throw "Calling isSuccessful on incomplete SFuture is not allowed"
    else @_stateSet > 0

  # () -> Boolean
  isFailed: -> !@isSuccessful()

  # (A -> B) -> SFuture[B]
  map: (mapper) -> newPromise((p) =>
    @onComplete(
      (s) -> tryCompletingPromise(p, () -> mapper(s))
      passFailureToPromise(p)
    )

    return
  )

  # (A -> SFuture[B]) -> SFuture[B]
  flatMap: (flatMapper) -> newPromise((p) =>
    @onComplete(
      (s) ->
        try
          p.join(flatMapper(s))
        catch error
          p.failure(error)
      passFailureToPromise(p)
    )

    return
  )

  # (A -> Boolean) -> SFuture[A]
  filter: (filter) -> newPromise((p) =>
    @onComplete(
      (s) ->
        if filter(s) then p.success(s)
        else p.failure("SFuture.filter predicate is not satisfied")
      passFailureToPromise(p)
    )

    return
  )

  # Zip `this` and `that` futures, resulting new future, contained an array with a results of two futures
  #
  # (SFuture[B]) -> SFuture[(A, B)]
  zip: (that) -> newPromise((p) =>
    @onComplete(
      (s) -> that.onComplete(
        (thatS) -> p.success([s, thatS])
        passFailureToPromise(p)
      )
      passFailureToPromise(p)
    )

    return
  )

  # Fallback to passed future if this future fails
  #
  # (SFuture[A]) -> SFuture[A]
  fallbackTo: (that) -> newPromise((p) =>
    @onComplete(
      passSuccessToPromise(p)
      (e) -> that.onComplete(
        passSuccessToPromise(p)
        () -> p.failure(e) # Use the first failure as the failure
      )
    )

    return
  )

  # ((String) -> B) -> SFuture[B]
  recover: (f) -> newPromise((p) =>
    @onComplete(
      passSuccessToPromise(p)
      (e) -> tryCompletingPromise(p, () -> f(e))
    )

    return
  )

  # ((String) -> SFuture[B]) -> SFuture[B]
  recoverWith: (f) -> newPromise((p) =>
    @onComplete(
      passSuccessToPromise(p)
      (e) ->
        p.join(
          try f(e)
          catch error
            SFuture.failed(error)
        )

        return
    )

    return
  )

  # Same as onComplete, but used for chaining side-effecting operations with normal operations
  #
  # (A -> Unit, String -> Unit) -> SFuture[A]
  andThen: (sf, ff) -> newPromise((p) =>
    @onComplete(
      (s) ->
        sf(s)
        p.success(s)
      (e) ->
        ff(e)
        p.failure(e)
    )

    return
  )

`export default {
  Future: SFuture,
  Promise: SPromise
}`