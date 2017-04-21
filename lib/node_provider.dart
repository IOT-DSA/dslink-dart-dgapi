part of dglux.dgapi;

final RegExp FIX_PATH_REGEX = new RegExp(r"\/\/(.*)\/");

String convertDsaToNiagara(String input) {
  if (input == "") {
    input = "/";
  }

  if (input.startsWith("/config")) {
    var part = input.substring("/config".length);
    return "slot:${part}";
  } else if (input.startsWith("/history")) {
    if (input == "/history") {
      return "history:";
    } else if (input == "/history/_default") {
      return "history:///";
    } else {
      var p = input.substring("/history".length);
      if (p.startsWith("/_default")) {
        p = p.substring("/_default".length);
      }
      p = "history:${p}".replaceAll("__SLASH__", "/");
      if (p.startsWith("history:__SLASH__")) {
        p = "history:/" + p.substring(17);
      }

      if (p.startsWith("history:/history:/")) {
        p = p.substring(9);
      }

      if (p.contains("/__OR__")) {
        p = p.replaceAll("/__OR__", "|");
      }

      if (p.contains("|")) {
        return p.split("|").skip(1).join("|");
      }

      return p;
    }
  } else if (input.startsWith("/")) {
    return input;
  }

  throw new Exception("ERROR: ${input} is not supported.");
}

String convertNiagaraToDsa(String input) {
  if (input.startsWith("slot:")) {
    var real = input.split("/").skip(1).join("/");
    var out = "/config";
    out += real;
    return out;
  } else if (input.startsWith("history:")) {
    if (input == "history:") {
      return "/history";
    } else if (input == "history:///") {
      return "/history/_default";
    } else if (input.startsWith("history:/") && !input.startsWith("history://")) {
      var name = input.split("history:/").last;
      return "/history/_default/${name}";
    } else {
      var path = "/history" + input.substring("history:/".length);
      path = path.replaceAllMapped(FIX_PATH_REGEX, (m) {
        return "/__SLASH__" + m.group(1) + "/";
      });
      return path;
    }
  } else {
    return input;
  }
}

class DgApiNodeProvider extends SimpleNodeProvider implements SerializableNodeProvider {
  IPermissionManager permissions = new DummyPermissionManager();
  Map<String, DGDataService> services = {};

  @override
  Map<String, LocalNode> nodes = new Map<String, LocalNode>();

  @override
  LocalNode getNode(String path) {
    if (nodes.containsKey(path)) {
      return nodes[path];
    }

    // don't cache in nodes map, it's only for running subscription
    // other nodes are just used once and throw away
    var nm = path.indexOf("/", 1);
    String conn = path.length > 1 ? path.substring(1, nm < 0 ? null : nm) : "";

    if (!services.containsKey(conn)) {
      return new SimpleNode(path);
    }

    var n = new DgApiNode(conn, path, this);
    n.rpath = n.path.substring(conn.length + 1);

    if (path == "/${conn}") {
      if (nodes.containsKey("/${conn}/dbQuery")) {
        n.children["dbQuery"] = nodes["/${conn}/dbQuery"];
      }

      if (nodes.containsKey("/${conn}/Delete_Connection")) {
        n.children["Delete_Connection"] = nodes["/${conn}/Delete_Connection"];
      }

      nodes[path] = n;
    }

    return n;
  }

  @override
  LocalNode getOrCreateNode(String path, [bool addToTree = true, bool init = true]) {
    return getNode(path);
  }

  LocalNode operator [](String path) {
    return getNode(path);
  }

  /// register node for subscribe or list api
  void registerNode(String conn, DgApiNode node) {
    if (nodes.containsKey(node.path)) {
      if (nodes[node.path] == node) {
        return;
      }
      print('error: OldApiNodeProvider.addSubscribeNode, node mismatch');
    }
    nodes[node.path] = node;
  }

  void unregisterNode(DgApiNode node) {
    if (nodes[node.path] == node) {
      nodes.remove(node.path);
    }
  }

  void addConnection(String name, String url, String username, String password) {
    IOldApiConnection connection = new OldApiBaseAuthConnection(url, username, password);

    var nd = new DGNode('/$name', this);
    nodes['/'].addChild(name, nd);

    int tryAgain = 0;

    void setup() {
      var stub = nodes['/']?.getChild(name) as SimpleNode;
      if (stub != null) {
        stub.remove();
      }

      services[name] = connection.service;
      SimpleNode node = new SimpleNode("/", this);

      node.load({
        r"$$dgapi_url": url,
        r"$$dgapi_username": username,
        r"$$dgapi_password": password
      });

      var dbQueryNode = new SimpleActionNode("/$name/dbQuery", (Map<String, dynamic> params) {
        var r = new AsyncTableResult();
        var db = params["db"];
        var query = params["query"];
        connection.service.queryDatabase(db, query).then((result) {
          r.columns = result["columns"];
          r.update(result["rows"], StreamStatus.closed);
        }).catchError((e) {
          r.close();
        });

        return r;
      }, this);

      var conn = name;

      var deleteConnectionNode = new SimpleActionNode("/$conn/Delete_Connection", (Map<String, dynamic> params) {
        if (connection.service._watchTimer != null) {
          connection.service._watchTimer.dispose();
        }

        removeNode("/$conn");
        nodes.keys.toList().forEach((path) {
          if (path == "/$conn" || path.startsWith("/$conn/")) {
            nodes.remove(path);
          }
        });
        saveLink();
      });

      dbQueryNode.load({
        r"$name": "Query Database",
        r"$invokable": "write",
        r"$params": [
          {
            "name": "db",
            "type": "enum[]"
          },
          {
            "name": "query",
            "type": "string"
          }
        ],
        r"$result": "table",
        r"$columns": []
      });

      deleteConnectionNode.load({
        r"$name": "Delete Connection",
        r"$invokable": "write",
        r"$result": "values"
      });

      node.addChild("dbQuery", dbQueryNode);
      nodes["/$name/dbQuery"] = dbQueryNode;
      node.addChild("Delete_Connection", deleteConnectionNode);
      nodes["/$name/Delete_Connection"] = deleteConnectionNode;

      connection.service.listDatabases().then((dbs) {
        (dbQueryNode.configs[r"$params"] as List)[0]["type"] = buildEnumType(dbs);
        dbQueryNode.listChangeController.add(r"$params");
      });

      nodes["/"].addChild(name, node);
    }

    var retries = 0;
    void makeTry() {
      retries++;
      connection.loginWithError().then((_) {
        logger.fine("Connection to '$name' succeeded.");
        setup();
        if (tryAgain == 0) {
          ll++;
        }
        nx++;
      }).catchError((e) {
        if (retries < 5) {
          print("Warning: Failed to connect for connection $name: $e");
        }

        logger.fine("Warning: Failed to connect for connection $name: $e");

        if (tryAgain == 0) {
          ll++;
        }

        if (tryAgain <= 0) {
          tryAgain = 1;
        }

        tryAgain += tryAgain * 2;

        if (tryAgain >= 60) {
          tryAgain = 2;
        }

        Scheduler.after(new Duration(seconds: tryAgain), () {
          makeTry();
        });
      });
    }

    makeTry();
  }

  Map<String, IconModel> icons = {};

  @override
  void init([Map m, Map profiles]) {
    if (m == null) return;
    if (m[r'$$writeActions'] is String) {
      String actions = m[r'$$writeActions'];
      DgSimpleActionNode.writeActions = actions.split(',');
      getNode('/Update_Write_Actions').configs[r"$params"] = [
        {
          "name": "actions",
          "type": "string",
          "editor": "textarea",
          "description": "actions that needs write permission, comma seperated",
          "placeholder": "",
          "default": actions
        }
      ];
    }
    var names = m.keys.where((it) => !it.startsWith(r"$") &&
      it != "Add_Connection" && it != 'Update_Write_Actions'
    ).toList();
    nx = names.length;
    bool hasBrokenPassword = false;
    for (var n in names) {
      var url = m[n][r"$$dgapi_url"];
      var username = m[n][r"$$dgapi_username"];
      var raw_password = m[n][r"$$dgapi_password"];
      String password;
      if (raw_password is String) {
        if (raw_password.length == 22) {
          hasBrokenPassword = true;
        }
        password = SimpleNode.decryptString(raw_password);
      }
      addConnection(n, url, username, password);
    }

    setIconResolver((String path) async {
      if (icons.containsKey(path)) {
        var bytes = await icons[path].fetch();
        return ByteDataUtil.fromList(bytes);
      }
      return null;
    });
    if (hasBrokenPassword) {
      saveLink();
    }

  }

  int ll = 0;
  int nx = -1;

  @override
  Map save() {
    var m = {
      r"$is": "node"
    };

    for (var x in services.keys.toList()) {
      if (!nodes["/"].children.containsKey(x)) {
        services.remove(x);
        continue;
      }
      var c = nodes["/"].children[x].configs;
      m[x] = {
        r"$$dgapi_url": c[r"$$dgapi_url"],
        r"$$dgapi_username": c[r"$$dgapi_username"],
        r"$$dgapi_password": SimpleNode.encryptString(c[r"$$dgapi_password"])
      };
    }
    m[r"$$writeActions"] = DgSimpleActionNode.writeActions.join(',');
    return m;
  }

  @override
  LocalNode operator ~() {
    return getNode("/");
  }

  Responder createResponder(String dsId, String sessionId) {
    return new Responder(this);
  }
}

class IconModel {
  final DGDataService service;
  final String path;
  final String url;

  IconModel(this.service, this.path, this.url);

  Future<List<int>> fetch() async {
    return await service.connection.loadBytes(Uri.parse(url));
  }
}
