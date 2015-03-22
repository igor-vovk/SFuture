define(["exports", "module"], function (exports, module) {
  "use strict";

  var SFuture, SPromise, isFunction, newPromise, passFailureToPromise, passSuccessToPromise, tryCompletingPromise;

  passSuccessToPromise = function (p) {
    return function (s) {
      return p.success(s);
    };
  };

  passFailureToPromise = function (p) {
    return function (e) {
      return p.failure(e);
    };
  };

  newPromise = function (f) {
    var p;
    p = new SPromise();
    f(p);
    return p.future();
  };

  tryCompletingPromise = function (p, f) {
    var error, success, val;
    val = null;
    error = null;
    success = false;
    try {
      val = isFunction(f) ? f() : f;
      success = true;
    } catch (_error) {
      error = _error;
    } finally {
      if (success) {
        p.success(val);
      } else {
        p.failure(error);
      }
    }
  };

  isFunction = function (a) {
    return typeof a === "function";
  };

  SPromise = (function () {
    SPromise.successful = function (result) {
      var p;
      p = new SPromise();
      p.success(result);
      return p;
    };

    SPromise.failed = function (err) {
      var p;
      p = new SPromise();
      p.failure(err);
      return p;
    };

    function SPromise() {
      this._ref = null;
    }

    SPromise.prototype.future = function () {
      if (this._ref === null) {
        this._ref = new SFuture();
      }
      return this._ref;
    };

    SPromise.prototype.isCompleted = function () {
      return this._ref !== null && this._ref.isCompleted();
    };

    SPromise.prototype.join = function (otherFuture) {
      otherFuture.onComplete(passSuccessToPromise(this), passFailureToPromise(this));
    };

    SPromise.prototype.success = function (value) {
      this.future().setState(value);
    };

    SPromise.prototype.failure = function (cause) {
      this.future().setState(cause, false);
    };

    return SPromise;
  })();

  SFuture = (function () {
    SFuture.apply = function (func, timeout) {
      if (timeout == null) {
        timeout = 0;
      }
      return newPromise(function (p) {
        var delayedF;
        delayedF = function () {
          tryCompletingPromise(p, func);
        };
        setTimeout(delayedF, timeout);
      });
    };

    SFuture.failed = function (err) {
      return SPromise.failed(err).future();
    };

    SFuture.successful = function (result) {
      return SPromise.successful(result).future();
    };

    SFuture.sequence = function (futures) {
      var result;
      result = SFuture.successful([]);
      futures.forEach(function (future) {
        result = result.flatMap(function (r) {
          return future.map(function (v) {
            r.push(v);
            return r;
          });
        });
      });
      return result;
    };

    SFuture.traverse = function (list, fn) {
      var result;
      result = SFuture.successful([]);
      list.forEach(function (item) {
        var fb;
        fb = fn(item);
        result = result.flatMap(function (items) {
          return fb.map(function (res) {
            items.push(res);
            return items;
          });
        });
      });
      return result;
    };

    SFuture.firstCompletedOf = function (futures) {
      return newPromise(function (p) {
        var f, i, len;
        for (i = 0, len = futures.length; i < len; i++) {
          f = futures[i];
          p.join(f);
        }
      });
    };

    function SFuture() {
      this._handlers = {
        s: [],
        f: []
      };
      this._stateSet = 0;
      this._state = null;
    }

    SFuture.prototype.setState = function (s, succ) {
      var exc, exceptions, h, i, len, ref;
      if (succ == null) {
        succ = true;
      }
      if (this.isCompleted()) {
        return;
      }
      this._state = s;
      this._stateSet = succ ? 1 : -1;
      exceptions = [];
      ref = succ ? this._handlers.s : this._handlers.f;
      for (i = 0, len = ref.length; i < len; i++) {
        h = ref[i];
        if (isFunction(h)) {
          try {
            h(s);
          } catch (_error) {
            exc = _error;
            exceptions.push(exc);
          }
        }
      }
      this._handlers = null;
      if (exceptions.length > 0) {
        throw "Exceptions thrown while executing callbacks: " + exceptions.join(", ");
      }
    };

    SFuture.prototype.onSuccess = function (cb) {
      if (this.isCompleted()) {
        if (this.isSuccessful()) {
          cb(this._state);
        }
      } else {
        this._handlers.s.push(cb);
      }
    };

    SFuture.prototype.onFailure = function (cb) {
      if (this.isCompleted()) {
        if (!this.isSuccessful()) {
          cb(this._state);
        }
      } else {
        this._handlers.f.push(cb);
      }
    };

    SFuture.prototype.onComplete = function (success, failure) {
      this.onSuccess(success);
      this.onFailure(failure);
    };

    SFuture.prototype.isCompleted = function () {
      return this._stateSet !== 0;
    };

    SFuture.prototype.isSuccessful = function () {
      if (!this.isCompleted()) {
        throw "Calling isSuccessful on incomplete SFuture is not allowed";
      } else {
        return this._stateSet > 0;
      }
    };

    SFuture.prototype.isFailed = function () {
      return !this.isSuccessful();
    };

    SFuture.prototype.map = function (mapper) {
      return newPromise((function (_this) {
        return function (p) {
          _this.onComplete(function (s) {
            return tryCompletingPromise(p, function () {
              return mapper(s);
            });
          }, passFailureToPromise(p));
        };
      })(this));
    };

    SFuture.prototype.flatMap = function (flatMapper) {
      return newPromise((function (_this) {
        return function (p) {
          _this.onComplete(function (s) {
            var error;
            try {
              return p.join(flatMapper(s));
            } catch (_error) {
              error = _error;
              return p.failure(error);
            }
          }, passFailureToPromise(p));
        };
      })(this));
    };

    SFuture.prototype.filter = function (filter) {
      return newPromise((function (_this) {
        return function (p) {
          _this.onComplete(function (s) {
            if (filter(s)) {
              return p.success(s);
            } else {
              return p.failure("SFuture.filter predicate is not satisfied");
            }
          }, passFailureToPromise(p));
        };
      })(this));
    };

    SFuture.prototype.zip = function (that) {
      return newPromise((function (_this) {
        return function (p) {
          _this.onComplete(function (s) {
            return that.onComplete(function (thatS) {
              return p.success([s, thatS]);
            }, passFailureToPromise(p));
          }, passFailureToPromise(p));
        };
      })(this));
    };

    SFuture.prototype.fallbackTo = function (that) {
      return newPromise((function (_this) {
        return function (p) {
          _this.onComplete(passSuccessToPromise(p), function (e) {
            return that.onComplete(passSuccessToPromise(p), function () {
              return p.failure(e);
            });
          });
        };
      })(this));
    };

    SFuture.prototype.recover = function (f) {
      return newPromise((function (_this) {
        return function (p) {
          _this.onComplete(passSuccessToPromise(p), function (e) {
            return tryCompletingPromise(p, function () {
              return f(e);
            });
          });
        };
      })(this));
    };

    SFuture.prototype.recoverWith = function (f) {
      return newPromise((function (_this) {
        return function (p) {
          _this.onComplete(passSuccessToPromise(p), function (e) {
            var error;
            p.join((function () {
              try {
                return f(e);
              } catch (_error) {
                error = _error;
                return SFuture.failed(error);
              }
            })());
          });
        };
      })(this));
    };

    SFuture.prototype.andThen = function (sf, ff) {
      return newPromise((function (_this) {
        return function (p) {
          _this.onComplete(function (s) {
            sf(s);
            return p.success(s);
          }, function (e) {
            ff(e);
            return p.failure(e);
          });
        };
      })(this));
    };

    return SFuture;
  })();

  module.exports = {
    Future: SFuture,
    Promise: SPromise
  };
});
//# sourceMappingURL=index.js.map