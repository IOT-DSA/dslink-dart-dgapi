part of dglux.dgapi;

typedef void DataCallback(Map data);

typedef void StringCallback(String err);

class QueryToken {
  static void canceledCallback(Map obj) {
    // do nothing
  }

  int rid;
  Map request;
  DataCallback callback;
  Map meta;

  QueryToken(this.request, this.callback, [this.meta]);

  void cancel() {
    callback = canceledCallback;
  }

  bool get canceled => callback == canceledCallback;

  Map partialResponse;
  List partialItems;

  Map mergePartial(Map part) {
    Map partial = part['partial'];

    int from = partial['from'];
    int total = partial['total'];
    List items = partial['items'];

    if (partialResponse == null) {
      part.remove('partial');
      partialResponse = part;
      partialItems = items;
    } else {
      partialItems.addAll(items);
    }
    if (from + items.length >= total) {
      String field = partial['field'];
      List fields = field.split('.');
      String lastField = fields.removeLast();
      Map target = partialResponse;
      for (String s in fields) {
        if (target[s] is Map) {
          target = target[s];
        } else {
          print('Error, partial result field not fount');
          return partialResponse;
        }
      }
      target[lastField] = partialItems;
      return partialResponse;
    }
    return null;
  }
}

class DGDataService {
  bool dgbox = false;
  static Math.Random _rnd = new Math.Random();
  static String subscriptionId = () {
    return 'DG${_rnd.nextInt(999999)}${_rnd.nextInt(999999)}';
  }();

  String hostUrl;
  Uri dataUri;
  String dbUrl;
  IOldApiConnection connection;
  int _reqId = 1;

  DGDataService(this.hostUrl, String dataUrl, this.dbUrl, this.connection) {
    dataUri = Uri.parse(dataUrl);
  }

  // list of pending req
  List<QueryToken> pendingReqList;

  void sendRequest(QueryToken token) {
    if (pendingReqList == null) {
      pendingReqList = [];
      startSendRequest();
    }
    int reqId = _reqId++;
    token.rid = reqId;
    token.request['reqId'] = reqId;

    pendingReqList.add(token);
  }

  List<String> dbs = [];

  Future<List<String>> listDatabases() async {
    try {
      var result = await connection.loadString(Uri.parse(dbUrl + "?op=list"));
      return JSON.decode(result);
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> queryDatabase(String db, String query) async {
    db = Uri.encodeComponent(db);
    query = Uri.encodeComponent(query);

    try {
      return JSON.decode(await connection.loadString(Uri.parse(dbUrl + "?db=${db}&query=${query}")));
    } catch (e) {
      print(e);
      return {
        "columns": [],
        "rows": []
      };
    }
  }

  void startSendRequest() {
    DsTimer.callLaterOnce(doSendRequest);
  }

  doSendRequest() async {
    prepareWatch();
    List<QueryToken> waitingList = pendingReqList;
    pendingReqList = null;

    String reqString = JSON.encode({
      "requests": waitingList.map((token) => token.request).toList(),
      "subscription": "$subscriptionId"
    });

    void onLoadError(String err) {
      for (var token in waitingList) {
        token.callback({'error': err});
      }
    }
    List responseData;
    try {
      String str = await connection.loadString(dataUri, reqString);

      Map data = JSON.decode(str);
      responseData = data['responses'];
    } catch (e) {
      onLoadError(e.toString());
      return;
    }
    if (responseData == null || responseData.length != waitingList.length) {
      onLoadError("response length doesn't match request length");
      return;
    }
    int len = responseData.length;
    for (int i = 0; i < len; ++i) {
      Object resData = responseData[i];
      QueryToken token = waitingList[i];
      if (resData is Map) {
        try {
          token.callback(resData);
        } catch (e) {
        }
      } else {
        token.callback({'error': 'invalid response'});
      }
    }
  }

  Timer _watchTimer;
  Map<String, DataCallback> watchs = new Map<String, DataCallback>();

  void addWatch(DataCallback callback, String path) {
    if (watchs.containsKey(path)) {
      logger.severe('DGDataService watch added twice');
    }
    watchs[path] = callback;
    if (toNotWatch.contains(path)) {
      toNotWatch.remove(path);
    } else {
      if (toWatch.isEmpty) {
        if (pendingReqList == null) {
          pendingReqList = [];
          startSendRequest();
        }
      }
      toWatch.add(path);
    }
    if (_watchTimer == null) {
      _watchTimer = new Timer.periodic(new Duration(milliseconds:500), pollSubscription);
    }

  }

  void removeWatch(DataCallback callback, String path) {
    if (!watchs.containsKey(path) || watchs[path] != callback) {
      logger.severe('DGDataService watch removed twice');
    }
    watchs.remove(path);
    if (toWatch.contains(path)) {
      toWatch.remove(path);
    } else {
      if (toNotWatch.isEmpty) {
        if (pendingReqList == null) {
          pendingReqList = [];
          startSendRequest();
        }
      }
      toNotWatch.add(path);
    }
    if (watchs.isEmpty && _watchTimer != null) {
      _watchTimer.cancel();
      _watchTimer = null;
    }
  }

  List<String> toWatch = [];
  List<String> toNotWatch = [];

  void prepareWatch() {
    if (!toWatch.isEmpty) {
      Map m = {
        "method": "Subscribe",
        "name": subscriptionId,
        "paths":toWatch
      };
      toWatch = [];
      subscribeToken = new QueryToken(m, subscriptionCallback);
      sendRequest(subscribeToken);
    }
    if (!toNotWatch.isEmpty) {
      Map m = {
        "method": "Unsubscribe",
        "name": subscriptionId,
        "paths":toNotWatch
      };
      toNotWatch = [];
      var token = new QueryToken(m, subscriptionCallback);
      sendRequest(token);
    }
  }

  QueryToken subscribeToken;

  void pollSubscription(Timer t) {
    if (subscribeToken != null) {
      return;
    }
    Map m = {
      "method": "PollSubscription",
      "name": subscriptionId,
    };
    subscribeToken = new QueryToken(m, subscriptionCallback);
    sendRequest(subscribeToken);
  }

  void subscriptionCallback(Map data) {
    subscribeToken = null;
    if (data['values'] is List) {
      for (Map m in data['values']) {
        String path = m['path'];
        if (path != null && watchs.containsKey(path)) {
          watchs[path](m);
        }
      }
    }
  }

  QueryToken invoke(
      DataCallback callback, String actionName, String path, Map parameters,
      {bool reuseReq: false, bool table: false, int streamCache: 0}) {
    Map m = {"method": "Invoke", "action": actionName, };
    if (path != null) {
      m['path'] = path;
    }
    if (parameters != null) {
      m['parameters'] = parameters;
    } else {
      m['parameters'] = const {};
    }
    var token = new QueryToken(m, callback);
    sendRequest(token);
    return token;
  }

  QueryToken getHistory(DataCallback callback, String path, String timeRange,
                        String interval, String rollup) {
    Map m = {
      "method": "GetValueHistory",
      "path": path,
      "timeRange": timeRange,
      "interval": interval,
      "rollup": rollup
    };
    var token = new QueryToken(m, callback);
    sendRequest(token);
    return token;
  }

  QueryToken getChildren(DataCallback callback, String parentPath) {
    Map m = {"method": "GetNodeList", "path": parentPath};
    var token = new QueryToken(m, (x) {
      callback(x);
    });
    sendRequest(token);
    return token;
  }

  QueryToken getNode(DataCallback callback, String path) {
    Map m = {"method": "GetNode", "path": path};
    var token = new QueryToken(m, callback);
    sendRequest(token);
    return token;
  }
}

class DGDataServiceAsync extends DGDataService {
  DGDataServiceAsync(String hostUrl, String dataUrl, String dbUrl, IOldApiConnection connection) :
  super(hostUrl, dataUrl, dbUrl, connection);

  bool needTimer() {
    return !watchs.isEmpty || !waitingIds.isEmpty || pendingReqList != null;
  }

  Object watching;

  void subscribeWatch(Timer t) {
    doSendRequest();
  }

  void startSendRequest() {
    if (_watchTimer == null) {
      _watchTimer = new Timer.periodic(new Duration(milliseconds: 500), subscribeWatch);
      DsTimer.callLaterOnce(doSendRequest);
    }
  }

  Map<int, QueryToken> waitingIds = {};

  bool _isPolling = false;

  @override
  void doSendRequest() {
    if (_isPolling) {
      return;
    }
    _isPolling = true;
    if (pendingReqList == null) {
      pendingReqList = [];
    }
    List<Map> reqDatas = [];
    for (var body in pendingReqList) {
      reqDatas.add(body.request);
      if (body.callback != null) {
        waitingIds[body.rid] = body;
      }
    }
    pendingReqList = null;
    String reqString = '{"requests":[${reqDatas.map((it) => JSON.encode(it)).join(',')}],"subscription":"${DGDataService.subscriptionId}"}';

    connection.loadString(dataUri, reqString).then((String result) {
      Map data;
      List responseData;
      try {
        data = DsJson.decode(result);
        responseData = data["responses"];
      } catch (e) {
        return;
      }
      int len = responseData.length;
      for (var i = 0; i < len; ++i) {
        Map resData = responseData[i];
        if (resData["reqId"] != null) {
          int id = resData["reqId"];
          if (id > 0) {
            QueryToken body = waitingIds[id];
            if (body == null) {
              continue;
            }
            if (resData is Map && resData["partial"] is Map) {
              resData = body.mergePartial(resData);
              if (resData == null) {
                continue;
              }
            }

            if (resData is Map) {
              try {
                body.callback(resData);
              } catch (e) {
              }
            } else {
            }
            waitingIds.remove(id);
          } else if (id < 0) {
            subscriptionCallback(resData);
          }
        }
      }

      checkClearTimer();
      _isPolling = false;
    });
  }

  void checkClearTimer() {
    if (_watchTimer != null && !needTimer()) {
      _watchTimer.cancel();
      _watchTimer = null;
    }
  }
}
