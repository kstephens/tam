NormalizedTime = {
  _make: function (db, t) {
    var x = { 
      Y: t.getUTCFullYear(),
      M: t.getUTCMonth() + 1,
      D: t.getUTCDate(),
      d: t.getUTCDay(),
      h: t.getUTCHours(),
      m: t.getUTCMinutes()
    };
    return x;
  },
  n: function (db, t) {
    var x = this._make(db, t);
    var y = db.nt.findOne(x);
    if ( ! y ) {
      db.nt.ensureIndex({Y:1, M:1, D:1, d:1, h:1, m:1});
      x._id = ObjectId();
      x.t = new Date(x.Y, x.M - 1, x.D, x.h, x.m, 0);
      db.nt.insert(x);
      y = x;
    }
    y = new DBRef(y._id, 'nt');
    return y;
  },
  find: function (db, t) {
    var x = this._make(db, t);
    var y = db.nt.find(x);
    if ( y ) {
      y = new DBRef(y._id, 'nt');
    }
    return y;
  },
  normalize_all: function (db, coll) {
    coll = db[coll];
    // coll.find({ nt: null }).
    coll.find().
      forEach(function (x) {
      x.nt = NormalizedTime.n(db, x.t);
      coll.save(x);
    })
  },
  END: null
};
