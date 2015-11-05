part of dglux.dgapi;

Function saveLink;

class DgApiNode extends SimpleNode {
  final String conn;
  DgApiNodeProvider provider;

  String rpath;

  DgApiNode(this.conn, String path, this.provider) : super(path);

  Node getChild(String name) {
    return provider.getNode('$path/$name');
  }

  int getInvokePermission() {
    return Permission.READ;
  }

  bool watching = false;
  bool valueReady = false;
  bool _niagara;
  bool get niagara {
    if (_niagara == null) {
      _niagara = provider.services[conn].niagara;
    }
    return _niagara;
  }

  String rewritePath(String x) {
    if (x.contains("definition%3A")) {
      x = x.replaceAll("/definition%3A", "|definition:").replaceAll("%2F", "/");
    }

    if (!niagara) {
      if (x == "") {
        x = "/";
      }

      if (x.contains("%2b")) {
        return x.replaceAll("%2b", "+");
      }

      return x;
    } else {
      return "slot:${x}";
    }
  }

  RespSubscribeListener subscribe(callback(ValueUpdate), [int qos = 0]) {
    if (!watching) {
      provider.registerNode(conn, this);
      provider.services[conn].addWatch(updateDataValue, rewritePath(rpath));
      watching = true;
    }
    return super.subscribe(callback, qos);
  }

  void unsubscribe(callback(ValueUpdate)) {
    super.unsubscribe(callback);
    if (watching && callbacks.isEmpty) {
      provider.services[conn].removeWatch(updateDataValue, rewritePath(rpath));
      watching = false;
      if (!_listing && path != "/${conn}") {
        provider.unregisterNode(this);
      }
      valueReady = false;
    }
  }

  updateDataValue(Map m) {
    updateValue(new ValueUpdate(m['value'], ts: m['lastUpdate']));
    valueReady = true;
  }

  InvokeResponse invoke(Map params, Responder responder, InvokeResponse response, LocalNode parentNode, [int maxPermission = Permission.CONFIG]) {
    List paths = rpath.split('/');
    String actName = paths.removeLast();

    void onError(String str) {
      // TODO: implement error
      response.close(new DSError('serverError'));
    }

    if (actName == 'getHistory') {
      var rollup = params['Rollup'];
      if (rollup == "none") {
        rollup = "default";
      }
      provider.services[conn].getHistory((Map rslt) {
        if (rslt['columns'] is List && rslt['rows'] is List) {
          List rows = rslt['rows'];
          List cols = rslt['columns'];
          response.updateStream(rows, columns: cols, streamStatus: StreamStatus.closed);
        } else {
          onError(rslt['error']);
        }
      }, rewritePath(paths.join("/")), params['Timerange'], mapInterval(params['Interval']), rollup);
    } else if (actName == 'dbQuery') {
    } else {
      provider.services[conn].invoke((Map rslt) {
        if (rslt['results'] is Map || rslt["error"] == null || rslt['result'] is Map) {
          Map results = rslt['results'];

          if (results == null) {
            results = {};
          }

          List row = [];
          List col = [];

          if (results.length == 1 && results[results.keys.first] is Map && results[results.keys.first].containsKey("columns")) {
            var rx = results[results.keys.first];
            response.updateStream(rx["rows"], columns: rx["columns"],
                streamStatus: StreamStatus.closed);
          } else if (rslt["result"] is Map) { // Simple Table Implementation
            var r = rslt["result"];
            if (r["columns"] is! List || r["rows"] is! List) {
              onError("Columns or rows does not exist.");
            } else {
              col = r["columns"].map((x) {
                if (x is Map && x["rawName"] is String) {
                  return {
                    "name": x["rawName"],
                    "type": x["type"]
                  };
                }
                return x;
              }).toList();
              row = r["rows"];
              response.updateStream(row, columns: col, streamStatus: StreamStatus.closed);
            }
          } else {
            results.forEach((k, v) {
              if (v is String || k == null) {
                col.add({'name': k, 'type':'string'});
              } else if (v is num) {
                col.add({'name': k, 'type':'number'});
              } else if (v is bool) {
                col.add({'name': k, 'type':'bool'});
              } else {
                return;
              }
              row.add(v);
            });
            response.updateStream([row], columns: col, streamStatus: StreamStatus.closed);
          }
        } else {
          onError(rslt['error']);
        }
      }, actName, rewritePath(paths.join("/")), params);
    }

    return response;
  }

  @override
  Map getSimpleMap() {
    var map = getSimpleMap();

    if (configs[r"$hasHistory"] != null) {
      map[r"$hasHistory"] = configs[r"$hasHistory"];
    }

    if (attributes["@icon"] != null) {
      map["@icon"] = attributes["@icon"];
    }

    return map;
  }

  bool _listing = false;
  bool listReady = false;

  void onStartListListen() {
    _listing = true;
    listNode();

    provider.registerNode(conn, this);
  }

  void onAllListCancel() {
    _listing = false;
    if (callbacks.isEmpty && path != "/${conn}") {
      provider.unregisterNode(this);
    }
    listReady = false;
  }

  void listNode() {
    if (!_listing) {
      return;
    }

    _nodeReady = false;
    _childrenReady = false;

    if (!provider.services[conn].actionHints.contains(rpath)) {
      provider.services[conn].getNode(getNodeCallback, rewritePath(rpath));
    } else {
      List paths = rewritePath(rpath).split('/');
      checkActionName = paths.removeLast();
      provider.services[conn].getNode(getParentNodeCallback, paths.join('/'));
    }
  }

  bool _nodeReady;
  Map node;

  void getNodeCallback(Map rslt) {
    if (rslt['node'] is Map) {
      node = rslt['node'];
    } else {
      node = null;
    }

    if (node != null && (node["hasChildren"] == true)) {
      provider.services[conn].getChildren(getChildrenCallback, rewritePath(rpath));
    } else {
      _childrenReady = true;
    }

    if (node != null && node["hasHistory"] == true) {
      configs[r"$hasHistory"] = true;
    }

    _nodeReady = true;
    if (_childrenReady) {
      listFinished();
    }
  }

  bool _childrenReady;
  List childrenNodes;

  void getChildrenCallback(Map rslt) {
    if (rslt['nodes'] is List) {
      childrenNodes = rslt['nodes'];
    } else {
      childrenNodes = null;
    }
    _childrenReady = true;
    if (_nodeReady) {
      listFinished();
    }
  }

  void getChildrenError(String) {
    this.childrenNodes = null;
    _childrenReady = true;
    if (_nodeReady) {
      listFinished();
    }
  }

  void listFinished() {
    if (node == null) {
      // node error? check if this is a action node from parent
      var m = rewritePath(rpath).split("/");
      checkActionName = m.removeLast();
      provider.services[conn].getNode(getParentNodeCallback, m.join("/"));
      return;
    }

    listReady = true;
    configs[r'$is'] = 'node';
    if (path != "/${conn}") {
      configs[r"$name"] = node["name"];
    }

    if (node['type'] is String) {
      configs[r'$type'] = node['type'];
    }

    if (node['enum'] is String) {
      if (node['type'] == 'bool') {
        configs[r'$type'] = 'bool[${node['enum']}]';
      } else {
        configs[r'$type'] = 'enum[${node['enum']}]';
      }
    }

    if (node['unit'] is String) {
      attributes['@unit'] = node['unit'];
    }

    if (node['actions'] is List) {
      for (Map action in node['actions']) {
        var nxr = action["name"];
        provider.services[conn].actionHints.add("${rpath}/${nxr}");
        children[nxr] = new DgSimpleActionNode(action);
      }
    }

/*
    if (node["icon"] is String) {
      var url = provider.services[conn].resolveIcon(node["icon"]);
      var uri = Uri.parse(url);
      var hash = new MD5();
      hash.add(UTF8.encode(uri.toString()));
      var hashz = CryptoUtils.bytesToHex(hash.close());
      var pn = "/dgapi/${hashz}";
//      attributes[r"@icon"] = pn;
      provider.icons[pn] = new IconModel(provider.services[conn], pn);
    }
*/

    if (childrenNodes != null) {
      for (Map n in childrenNodes) {
        String path = n["path"];
        String name;
        if (path.contains("|definition:")) {
          var parts = path.split("|");
          var n = parts.last;

          name = n.replaceFirst(":", "%3A").replaceAll("/", "%2F");
        } else {
          name = path.split("/").last.replaceAll("slot:", "");
        }

        if (name.contains("+")) {
          name = name.replaceAll("+", "%2b");
        }

/*        if (n["icon"] is String) {
          var url = provider.services[conn].resolveIcon(node["icon"]);
          var uri = Uri.parse(url);
          var hash = new MD5();
          hash.add(UTF8.encode(uri.toString()));
          var hashz = CryptoUtils.bytesToHex(hash.close());
          var pn = "/dgapi/${hashz}";
//          n["icon"] = pn;
          n.remove("icon");
          provider.icons[pn] = new IconModel(provider.services[conn], pn);
        }*/

        n.remove("icon");

        children[name] = new SimpleChildNode(n);
      }
    }

    if (node['hasHistory'] == true) {
      children['getHistory'] = _getHistoryNode;
      configs[r"$hasHistory"] = true;
    }

    // update is to refresh all;
    listChangeController.add(r'$is');
  }

  String checkActionName;

  void getParentNodeCallback(Map rslt) {
    if (rslt['node'] is Map) {
      Map pnode = rslt['node'];
      if (checkActionName == 'getHistory') {
        if (pnode['hasHistory'] == true) {
          listReady = true;
          configs.addAll(_getHistoryNode.configs);
        }
      } else if (checkActionName == 'dbQuery') {
      } else if (pnode['actions'] is List) {
        Map action = pnode['actions'].firstWhere((action) => action['name'] == checkActionName, orElse:() => null);
        if (action != null) {
          listReady = true;
          DgSimpleActionNode actionNode = new DgSimpleActionNode(action);
          configs.addAll(actionNode.configs);
        }
      }
      listChangeController.add(r'$is');
    } else {
      configs[r'$disconnectedTs'] = ValueUpdate.getTs();
      listChangeController.add(r'$disconnectedTs');
      listReady = true;
    }
  }
}

class DgSimpleActionNode extends SimpleNode {
  DgSimpleActionNode(Map action) : super('/') {
    configs[r'$is'] = 'node';
    configs[r'$invokable'] = 'read';
    configs[r"$name"] = action["name"].replaceAll("slot:", "").replaceAll("+", " ");
    if (action['parameters'] is List) {
      Map params = {};
      for (Map param in action['parameters']) {
        params[param['name']] = {'type': param['type']};
        if (param['enum'] is String && param['type'] != 'bool') {
          params[param['name']] = {'type': 'enum[${param["enum"]}]'};
        }
      }
      configs[r'$params'] = params;
    }

    if (action['results'] is List) {
      List columns = [];
      for (Map param in action['results']) {
        columns.add({'name': param['name'], 'type': param['type']});
      }
      if (action["results"].length == 1 && action["results"].first["type"] == "table") {
        configs[r"$result"] = "table";
      } else {
        configs[r"$result"] = "values";
      }
      configs[r'$columns'] = columns;
    }

    if (action['return'] == 'table') {
      configs[r"$result"] = "table";
    }
  }
}

class SimpleChildNode extends SimpleNode {
  SimpleChildNode(Map node) : super('/') {
    configs[r'$is'] = 'node';
    if (node['type'] is String) {
      configs[r'$type'] = node['type'];
    }

    configs[r"$name"] = node["name"].replaceAll("slot:", "").replaceAll("+", " ");
    if (node['enum'] is String) {
      configs[r'$type'] = 'enum[${node['enum']}]';
    }

    if (node['unit'] is String) {
      attributes['@unit'] = node['unit'];
    }

    if (node['icon'] is String) {
      configs[r'$icon'] = node['icon'];
    }
  }
}

const Map<String, String> intervalMap = const {
  "oneyear":"oneYear",
  "threemonths":"threeMonths",
  "onemonth":"oneMonth",
  "oneweek":"oneWeek",
  "oneday":"oneDay",
  "twelvehours":"twelveHours",
  "sixhours":"sixHours",
  "fourours":"fourHours",
  "threehours":"threeHours",
  "twohours":"twoHours",
  "onehour":"oneHour",
  "thirtyminutes":"thirtyMinutes",
  "twentyminutes":"twentyMinutes",
  "fifteenminutes":"fifteenMinutes",
  "tenminutes":"tenMinutes",
  "fiveminutes":"fiveMinutes",
  "oneminute":"oneMinute",
  "thirtyseconds":"thirtySeconds",
  "fifteenseconds":"fifteenSeconds",
  "tenseconds":"tenSeconds",
  "fiveseconds":"fiveSeconds",
  "onesecond":"oneSecond",
  "none":"none",
  "1y":"oneYear",
  "3n":"threeMonths",
  "1n":"oneMonth",
  "1w":"oneWeek",
  "1d":"oneDay",
  "12h":"twelveHours",
  "6h":"sixHours",
  "4h":"fourHours",
  "3h":"threeHours",
  "2h":"twoHours",
  "1h":"oneHour",
  "30m":"thirtyMinutes",
  "20m":"twentyMinutes",
  "15m":"fifteenMinutes",
  "10m":"tenMinutes",
  "5m":"fiveMinutes",
  "1m":"oneMinute",
  "20s":"thirtySeconds",
  "15s":"fifteenSeconds",
  "10s":"tenSeconds",
  "5s":"fiveSeconds",
  "1s":"oneSecond",
};

String mapInterval(String input) {
  if (input == null) return 'default';
  input = input.toLowerCase();
  if (intervalMap.containsKey(input)){
    return intervalMap[input];
  }
  return 'default';
}

SimpleNode _getHistoryNode = new SimpleNode('/')
  ..load({r'$is':'getHistory', r'$invokable':'read', r'$name': 'Get History'});
