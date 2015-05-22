part of dglux.dgapi;

class DgApiNode extends SimpleNode {
  final String conn;
  DgApiNodeProvider provider;

  String rpath;

  DgApiNode(this.conn, String path, this.provider) : super(path);

  bool watching = false;
  bool valueReady = false;

  RespSubscribeListener subscribe(callback(ValueUpdate), [int cachelevel = 1]){
    if (!watching) {
      provider.registerNode(conn, this);
      provider.services[conn].addWatch(updateDataValue, 'slot:$rpath');
      watching = true;
    }
    return super.subscribe(callback, cachelevel);
  }

  void unsubscribe(callback(ValueUpdate)) {
    super.unsubscribe(callback);
    if (watching && callbacks.isEmpty) {
      provider.services[conn].removeWatch(updateDataValue, 'slot:$rpath');
      watching = false;
      if (!_listing) {
        provider.unregisterNode(this);
      }
      valueReady = false;
    }
  }

  updateDataValue(Map m) {
    updateValue(new ValueUpdate(m['value'], ts:m['lastUpdate']));
    valueReady = true;
  }

  InvokeResponse invoke(Map params, Responder responder, InvokeResponse response) {
    List paths = rpath.split('/');
    String actName = paths.removeLast();
    void onError(String str) {
      // TODO: implement error
      response.close(new DSError('serverError'));
    }
    if (actName == 'getHistory') {
      provider.services[conn].getHistory((Map rslt) {
        if (rslt['columns'] is List && rslt['rows'] is List) {
          List rows = rslt['rows'];
          List cols = rslt['columns'];
          response.updateStream(rows, columns:cols, streamStatus: StreamStatus.closed);
        } else {
          onError(rslt['error']);
        }
      }, 'slot:${paths.join("/")}', params['Timerange'], params['Interval'], params['Rollup']);
    } else {
      provider.services[conn].invoke((Map rslt){
       if (rslt['results'] is Map) {
         Map results = rslt['results'];
         List row = [];
         List col = [];
         results.forEach((k,v) {
           if (v is String || k == null) {
             col.add({'name':k, 'type':'string'});
           } else if (v is num) {
             col.add({'name':k, 'type':'number'});
           } else if (v is bool) {
             col.add({'name':k, 'type':'bool'});
           } else{
             return;
           }
           row.add(v);
         });
         response.updateStream(row, columns:col, streamStatus: StreamStatus.closed);
       } else {
         onError(rslt['error']);
       }

     }, actName, 'slot:${paths.join("/")}',  params);
    }

    return response;
  }

  BroadcastStreamController<String> _listChangeController;
  BroadcastStreamController<String> get listChangeController {
    if (_listChangeController == null) {
      _listChangeController = new BroadcastStreamController<String>(
          _onStartListListen, _onAllListCancel);
    }
    return _listChangeController;
  }
  Stream<String> get listStream => listChangeController.stream;
  StreamSubscription _listReqListener;

  bool _listing = false;
  bool listReady = false;
  void _onStartListListen() {
    _listing = true;
    listNode();

    provider.registerNode(conn, this);
  }

  void _onAllListCancel() {
    _listing = false;
    if (callbacks.isEmpty) {
      provider.unregisterNode(this);
    }
    listReady = false;
  }

  void listNode(){
    if (!_listing) return;

    _nodeReady = false;
    _childrenReady = false;
    provider.services[conn].getNode(getNodeCallback, 'slot:$rpath');
    provider.services[conn].getChildren(getChildrenCallback, 'slot:$rpath');
  }
  bool _nodeReady;
  Map node;
  void getNodeCallback(Map rslt) {
    if (rslt['node'] is Map) {
      node = rslt['node'];
    } else {
      node = null;
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
      List paths = 'slot:$rpath'.split('/');
      checkActionName = paths.removeLast();
      provider.services[conn].getNode(getParentNodeCallback, paths.join('/') );
      return;
    }
    listReady = true;
    configs[r'$is'] = 'node';
    if (node['type'] is String) {
      configs[r'$type'] = node['type'];
    }
    if (node['enum'] is String) {
      configs[r'$type'] = 'enum[${node['enum']}]';
    }
    if (node['unit'] is String) {
      attributes['@unit'] = node['unit'];
    }
    if (node['actions'] is List) {
      for (Map action in node['actions']) {
        children[action['name']] = new SimpleActionNode(action);
      }
    }
    if (childrenNodes != null) {
      for (Map n in childrenNodes) {
        children[(n['path'] as String).split('/').last] = new SimpleChildNode(n);
      }
    }
    if (node['hasHistory'] == true) {
      children['getHistory'] = _getHistoryNode;
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
      } else if (pnode['actions'] is List) {
         Map action = pnode['actions'].firstWhere((action)=>action['name'] == checkActionName, orElse:()=>null);
         if (action != null) {
           listReady = true;
           SimpleActionNode actionNode = new SimpleActionNode(action);
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

class SimpleActionNode extends SimpleNode {
  SimpleActionNode(Map action) : super('/') {
    configs[r'$is'] = 'node';
    configs[r'$invokable'] = 'read';
    if (action['parameters'] is List) {
      Map params = {};
      for (Map param in action['parameters']) {
        params[param['name']] = {'type':param['type']};
        if (param['enum'] is String) {
          params[param['name']] = {'type':'enum[${param["enum"]}]'};
        }
      }
      configs[r'$params'] = params;
    }

    if (action['results'] is List) {
      List columns = [];
      for (Map param in action['results']) {
          columns.add({'name':param['name'], 'type':param['type']});
      }
      configs[r'$columns'] = columns;
    }
  }
}

class SimpleChildNode extends SimpleNode {
  SimpleChildNode(Map node) : super('/') {
    configs[r'$is'] = 'node';
    if (node['type'] is String) {
      configs[r'$type'] = node['type'];
    }
    if (node['enum'] is String) {
      configs[r'$type'] = 'enum[${node['enum']}]';
    }
    if (node['unit'] is String) {
      attributes['@unit'] = node['unit'];
    }
  }
}

SimpleNode _getHistoryNode = new SimpleNode('/')..load({r'$is':'getHistory', r'$invokable':'read'}, null);
