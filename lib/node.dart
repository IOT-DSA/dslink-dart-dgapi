part of dglux.dgapi;

class OldApiNode extends SimpleNode implements IDGDataWatcher{
  DgApiNodeProvider provider;
  
  OldApiNode(String path, this.provider) : super(path) {
  }
  
  bool watching = false;
  bool valueReady = false;
  
  RespSubscribeListener subscribe(callback(ValueUpdate), [int cachelevel = 1]){
    if (!watching) {
      provider.registerNode(this);
      provider.service.addWatch(updateDataValue, 'slot:$path');
      watching = true;
    }
    return super.subscribe(callback, cachelevel);
  }
  
  void unsubscribe(callback(ValueUpdate)) {
    super.unsubscribe(callback);
    if (watching && callbacks.isEmpty) {
      provider.service.removeWatch(updateDataValue, 'slot:$path');
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
    List paths = path.split('/');
    String actName = paths.removeLast();
    void onError(String str) {
      // TODO: implement error 
      response.close(new DSError('serverError'));
    }
    if (actName == 'getHistory') {
      provider.service.getHistory((Map table) {
//        List rows = table.rows.map((List row)=>row.sublist(1)).toList();
//        List cols = table.columns.sublist(1).map((col)=>{'name':col.name, 'type':col.type}).toList();
//        response.updateStream(rows, columns:cols, streamStatus: StreamStatus.closed);
      }, 'slot:${paths.join("/")}', params['Timerange'], params['Interval'], params['Rollup'], onError:onError);
    } else {
      provider.service.invoke((Map rslt){
       List row = [];
       List col = [];
       rslt.forEach((k,v) {
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
     }, actName, 'slot:${paths.join("/")}',  params, onError:onError);
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
    
    provider.registerNode(this);
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
    provider.service.getNode(getNodeCallback, 'slot:$path' ,onError:getNodeError);
    provider.service.getChildren(getChildrenCallback, 'slot:$path' ,onError:getChildrenError);
  }
  bool _nodeReady;
  DGDataNode node;
  void getNodeCallback(DGDataNode node) {
    this.node = node;
    _nodeReady = true;
    if (_childrenReady) {
      listFinished();
    }
  }
  void getNodeError(String str) {
    node = null;
    _nodeReady = true;
    if (_childrenReady) {
      listFinished();
    }
  }
  bool _childrenReady;
  List childrenNodes;
  void getChildrenCallback(List<DGDataNode> nodes) {
    this.childrenNodes = nodes;
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
      List paths = 'slot:$path'.split('/');
      checkActionName = paths.removeLast();
      provider.service.getNode(getParentNodeCallback, paths.join('/') ,onError:getParentNodeError);
      return;
    }
    listReady = true;
    configs[r'$is'] = 'node';
    if (node.type != null) {
      configs[r'$type'] = node.type;
    }
    if (node.enums != null) {
      configs[r'$type'] = 'enum[${node.enums}]';
    }
    if (node.unit != null) {
      attributes['@unit'] = node.unit;
    }
    if (node.actions != null) {
      for (DGDataAction action in node.actions) {
        children[action.name] = new SimpleActionNode(action);
      }
    }
    if (childrenNodes != null) {
      for (DGDataNode n in childrenNodes) {
        children[n.path.split('/').last] = new SimpleChildNode(n);
      }
    }
    if (node.hasHistory) {
      children['getHistory'] = _getHistoryNode;
    }
    // update is to refresh all;
    listChangeController.add(r'$is');
  }
  
  String checkActionName;
  void getParentNodeCallback(DGDataNode node) {
    if (checkActionName == 'getHistory') {
      if (node.hasHistory) {
        listReady = true;
        configs.addAll(_getHistoryNode.configs);
      }
    } else if (node.actions != null) {
      DGDataAction action = node.actions.firstWhere((action)=>action.name == checkActionName, orElse:()=>null);
      if (action != null) {
        listReady = true;
        SimpleActionNode actionNode = new SimpleActionNode(action);
        configs.addAll(actionNode.configs);
      }
    }
    listChangeController.add(r'$is');
  }
  void getParentNodeError(String str) {
    configs[r'$disconnectedTs'] = ValueUpdate.getTs();
    listChangeController.add(r'$disconnectedTs');
    listReady = true;
  }
}

class SimpleActionNode extends SimpleNode {
  SimpleActionNode(DGDataAction action) : super('/') {
    configs[r'$is'] = 'node';
    configs[r'$invokable'] = 'read';
    if (action.params != null) {
      Map params = {};
      for (DGDataParam param in action.params) {
        params[param.name] = {'type':param.type};
        if (param.enums != null) {
          params[param.name] = {'type':'enum[${param.enums.join(',')}]'};
        }
      }
      configs[r'$params'] = params;
    }
    
    if (action.results != null) {
      List columns = [];
      for (DGDataParam param in action.params) {
        if (param.enums != null) {
          columns.add({'name':param.name, 'type':'enum[${param.enums.join(',')}]'});
        } else {
          columns.add({'name':param.name, 'type':param.type});
        }
      }
      configs[r'$columns'] = columns;
    }
  }
}

class SimpleChildNode extends SimpleNode {
  SimpleChildNode(DGDataNode node) : super('/') {
    configs[r'$is'] = 'node';
    if (node.type != null) {
      configs[r'$type'] = node.type;
    }
    if (node.enums != null) {
      configs[r'$type'] = 'enum[${node.enums}]';
    }
    if (node.unit != null) {
      attributes['@unit'] = node.unit;
    }
  }
}

SimpleNode _getHistoryNode = new SimpleNode('/')..load({r'$is':'getHistory', r'$invokable':'read'}, null);