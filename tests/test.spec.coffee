a = require '../dist/commonjs/index'

rand = (max, min = 0) -> Math.floor(Math.random() * (max - min)) + min
r100 = -> rand(100)

describe "Create a promise", ->
  it "with not-completed future", () ->
    p = new a.Promise()
    f = p.future()

    expect(p.isCompleted()).not.toBeTruthy()
    expect(f.isCompleted()).not.toBeTruthy()
    expect(() -> f.isSuccessful()).toThrow()

  it "with completed successful future", (done) ->
    f = a.Promise.successful(1).future()

    expect(f.isCompleted()).toBeTruthy()
    expect(f.isSuccessful()).toBeTruthy()
    f.onSuccess((val) ->
      expect(val).toEqual 1

      done()
    )

  it "with completed failed future", (done) ->
    f = a.Promise.failed("exception").future()

    expect(f.isCompleted()).toBeTruthy()
    expect(f.isFailed()).toBeTruthy()
    f.onComplete(
      (val) -> throw "Future completed successfully while need to be failed"
      (e) ->
        expect(e).toEqual "exception"

        done()
    )

describe "Future itself", ->
  it "cannot be completed more than once", (done) ->
    p = new a.Promise()
    f = p.future()

    p.success(1)
    p.failure("Err")
    p.success(2)

    f.onComplete(
      (val) ->
        expect(val).toEqual 1

        done()
      (e) -> throw "Future failed while need to be successful, " + e
    )

describe "Creating future with", ->
  callback = null

  beforeEach ->
    callback = jasmine.createSpy("callback")
    jasmine.clock().install()

  afterEach ->
    jasmine.clock().uninstall()

  it "success method should create completed func", ->
    a.Future.successful(1).onSuccess(callback)

    expect(callback).toHaveBeenCalled()

  it "failed method should create completed func", ->
    a.Future.failed("err").onFailure(callback)

    expect(callback).toHaveBeenCalled()

  it "apply method should apply function after given timeout", ->
    time = r100()
    a.Future.apply(callback, time)

    expect(callback).not.toHaveBeenCalled()
    jasmine.clock().tick(time + 1)
    expect(callback).toHaveBeenCalled()


describe "Combining futures", ->

  describe "using sequence method", ->

    it "should return empty array if passed array is empty", (done) ->
      a.Future.sequence([]).onComplete(
        (val) ->
          expect(val).toEqual []

          done()
        (e) -> throw e
      )

    it "should create one future from array with futures", (done) ->
      futures = [a.Future.apply(1, r100()), a.Future.apply(3, r100()), a.Future.apply(5, r100())]

      a.Future.sequence(futures).onComplete(
        (val) ->
          expect(val).toEqual [1, 3, 5]

          done()
        (e) -> throw e
      )

  describe "using traverse method", ->

    fit "should return future with array, from array with values using mapper-function, which returns future", (done) ->
      futures = [a.Future.apply(1, r100()), a.Future.apply(3, r100()), a.Future.apply(5, r100())]
      flatMapper = (val) -> a.Future.apply(val, r100())

      a.Future.traverse(futures, flatMapper).onComplete(
        (val) ->
          expect(val).toEqual [30, 90, 150]

          done()
        (e) -> throw e
      )

  it "using firstCompletedOf method returns first completed future", (done) ->
    futures = [a.Future.apply(1, 20), a.Future.apply(5, 10), a.Future.apply(10, 0)]

    a.Future.firstCompletedOf(futures).onComplete(
      (val) ->
        expect(val).toEqual 10

        done()
      (e) -> throw e
    )

describe "Operation under future named", ->

  succF = null
  failF = null

  beforeAll(() ->
    succF = a.Future.successful(1)
    failF = a.Future.failed("Err")
  )

  it "map should change value", (done) ->
    succF.map((v) -> v + 1).onComplete(
      (val) ->
        expect(val).toEqual 2

        done()
      (e) -> throw e
    )

  it "flatMap should change value", (done) ->
    a.Future.successful([1, 2, 3])
      .flatMap((arr) ->
        # Some async computation based on `arr` value
        a.Future.successful(arr[0])
      )
      .onComplete(
        (val) ->
          expect(val).toEqual(1)

          done()
        (e) -> throw e
      )

  it "filter should pass or reject future", ->
    isEven = (a) -> a % 2 is 1
    isOdd = (a) -> a % 2 is 0

    expect(succF.filter(isEven).isSuccessful()).toBeTruthy()
    expect(succF.filter(isOdd).isFailed()).toBeTruthy()

  it "zip should combine value of this future with that", (done) ->
    thatF = a.Future.successful(2)
    thirdF = a.Future.successful(3)

    succF.zip(thatF).zip(thirdF).onComplete(
      (val) ->
        expect(val).toEqual [[1, 2], 3]

        done()
      (e) -> throw e
    )

  describe "fallbackTo", ->
    it "should not change value of this future if it not fails", (done) ->
      thatF = a.Future.successful(2)

      succF.fallbackTo(thatF).onSuccess (val) ->
        expect(val).toEqual 1

        done()

    it "should get value from that future if this future fails", (done) ->
      thatF = a.Future.successful(2)

      failF.fallbackTo(thatF).onSuccess (val) ->
        expect(val).toEqual 2

        done()

  it "recover should call passed function if this future fails", (done) ->
    failureHandler = (e) ->
      # console.log(e);
      1

    failF.recover(failureHandler).onSuccess (val) ->
      expect(val).toEqual 1

      done()

  it "recoverWith should call passed function if this future fails", (done) ->
    failureHandler = (e) ->
      # Some async computation
      a.Future.successful(5)

    failF.recoverWith(failureHandler).onSuccess (val) ->
      expect(val).toEqual 5

      done()

  it "andThen used to order side-effecting calls", (done) ->
    called =
      a: no
      b: no
      c: no

    succF
      .andThen(
        (v) ->
          expect(v).toEqual(1)
          expect(called).toEqual {a: no, b: no, c: no}

          v = 5
          called.a = yes
        (e) -> throw e
      )
      .map((v) -> v + 1)
      .andThen(
        (v) ->
          expect(v).toEqual(2)
          expect(called).toEqual {a: yes, b: no, c: no}

          v = 5
          called.b = yes
        (e) -> throw e
      )
      .map((v) -> v + 5)
      .andThen(
        (v) ->
          expect(v).toEqual(7)
          expect(called).toEqual {a: yes, b: yes, c: no}

          v = 5
          called.c = yes
        (e) -> throw e
      )
      .onSuccess(() ->
        expect(called).toEqual {a: yes, b: yes, c: yes}

        done()
      )
