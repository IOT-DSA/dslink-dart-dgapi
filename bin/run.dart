import 'dart:async';
import 'package:args/args.dart';
import 'package:dslink/dslink.dart';

import '../lib/dgapi.dart';

import 'package:http/http.dart' as http;

bool hasChanged = false;

main(List<String> args) async {
  DgApiNodeProvider provider = new DgApiNodeProvider();
  SimpleNode root = provider.nodes["/"] = new SimpleNode("/");

  provider.nodes["/Add_Connection"] = new AddConnectionNode("/Add_Connection");
  root.addChild("Add_Connection", provider.nodes["/Add_Connection"]);

  provider.nodes["/Clear_Disconnected"] = new RemoveDisconnectedConnsNode("/Clear_Disconnected");
  root.addChild("Clear_Disconnected", provider.nodes["/Clear_Disconnected"]);

  provider.nodes["/Update_Write_Actions"] =
  new WriteActionListNode("/Update_Write_Actions");
  root.addChild(
      "Update_Write_Actions", provider.nodes["/Update_Write_Actions"]);

  link = new LinkProvider(args, "dgapi-", nodeProvider: provider,
      isResponder: true,
      autoInitialize: false);

  var argp = new ArgParser();
  argp.addOption(
      "poll-interval",
      defaultsTo: "1000",
      help: "Poll Interval in Milliseconds"
  );

  link.configure(argp: argp, optionsHandler: (opts) {
    globalPollInterval =
        int.parse(opts["poll-interval"] == null ? 1000 : opts["poll-interval"]);
  });

  saveLink = () {
    hasChanged = true;
  };

  link.init();

  Scheduler.every(Interval.FIVE_SECONDS, () async {
    if (hasChanged) {
      hasChanged = false;
      await link.saveAsync();
    }
  });

  int count = 0;

  while (true) {
    count++;
    if (provider.nx == 0 || count == 500 ||
        (provider.nx != -1 && provider.ll == provider.nx)) {
      link.connect();
      break;
    } else {
      await new Future.delayed(const Duration(milliseconds: 5));
    }
  }
}

http.Client httpClient = new http.IOClient(loader);

Future<String> detectAndCorrectHost(String host) async {
  if (!host.endsWith("/")) {
    host += "/";
  }

  if (!host.startsWith("http://") && !host.startsWith("https://")) {
    host = "http://" + host;
  }

  if (host == "http://create.dglux.com/") {
    return "http://create.dglux.com/app/";
  }

  if (host == "https://create.dglux.com/") {
    return "https://create.dglux.com/app/";
  }

  http.Response response = await httpClient.get(host).timeout(
      const Duration(seconds: 5));

  var server = response.headers["server"];

  if (server == null) {
    return host;
  }

  if (server.contains("Jetty")) { // Detects Jetty Servers
    var uri = Uri.parse(host);

    if (response.headers.containsKey("location")) {
      var u = uri;
      u = u.resolve(response.headers["location"]);
      response = await httpClient.get(u.toString(), headers: {
        "x-niagara": "true" // Use Proxy on WKWebView
      }).timeout(const Duration(seconds: 5));
    }

    if (response.headers.containsKey("x-location")) {
      var u = uri;
      u = u.resolve(response.headers["x-location"]);
      response = await httpClient.get(u.toString(), headers: {
        "x-niagara": "true" // Use Proxy on WKWebView
      }).timeout(const Duration(seconds: 5));
    }

    if (response.body.contains("ENVYSION") ||
        response.body.contains("ECLYPSE")) {
      return uri.toString();
    }

    if ((response.body.contains("DGBox") || response.body.contains("DGBOX")) ||
        (response.headers["x-location"] != null &&
            response.headers["x-location"].contains("dgbox"))) {
      return uri.toString();
    }
  }

  if (response.body.contains("/enteliweb/")) {
    var uri = Uri.parse(host);
    return uri.toString();
  }

  if (server.contains("Niagara") || server.contains("Coyote")) {
    if (!host.endsWith("/dglux5/")) {
      host += "dglux5/";
    }
  }

  return host;
}

LinkProvider link;

class AddConnectionNode extends SimpleNode {
  AddConnectionNode(String path) : super(path) {
    load({
      r"$name": "Add Connection",
      r"$params": [
        {
          "name": "name",
          "type": "string",
          "description": "Connection Name",
          "placeholder": "OldServer"
        },
        {
          "name": "url",
          "type": "string",
          "description": "Url",
          "placeholder": "http://dgbox.example.com/dglux5/"
        },
        {
          "name": "username",
          "type": "string",
          "description": "Username",
        },
        {
          "name": "password",
          "type": "string",
          "editor": "password",
          "description": "Password"
        }
      ],
      r"$invokable": "config",
      r"$result": "values"
    });
  }

  @override
  onInvoke(Map<String, dynamic> params) async {
    String name = params["name"];
    String url = params["url"];
    String user = params["username"];
    String password = params["password"];

    url = await detectAndCorrectHost(url);

    IOldApiConnection connection = new OldApiBaseAuthConnection(
        url, user, password);
    await connection.login();
    DgApiNodeProvider provider = link.provider;
    provider.services[name] = connection.service;
    provider.nodes["/"].addChild(name, new SimpleNode("/")
      ..load({
        r"$$dgapi_url": url,
        r"$$dgapi_username": user,
        r"$$dgapi_password": password
      }));
    hasChanged = true;
    return {};
  }
}


class WriteActionListNode extends SimpleNode {
  WriteActionListNode(String path) : super(path) {
    load({
      r"$name": "Update Write Actions",
      r"$params": [
        {
          "name": "actions",
          "type": "string",
          "editor": "textarea",
          "description": "actions that needs write permission, comma seperated",
          "placeholder": "",
          "default": "Active,Auto,Emergency Active,Emergency Auto,Emergency Inactive,Inactive,Set,Override,Save"
        }
      ],
      r"$invokable": "config"
    });
  }

  @override
  onInvoke(Map<String, dynamic> params) async {
    Object actions = params["actions"];
    if (actions is String) {
      DgSimpleActionNode.writeActions = actions.split(',');
      this.configs[r"$params"] = [
        {
          "name": "actions",
          "type": "string",
          "editor": "textarea",
          "description": "actions that needs write permission, comma seperated",
          "placeholder": "",
          "default": actions
        }
      ];

      hasChanged = true;
    }
    return {};
  }
}

class RemoveDisconnectedConnsNode extends SimpleNode {
  RemoveDisconnectedConnsNode(String path) : super(path) {
    load({
      r"$name": "Remove Disconnected Connection",
      r"$invokable": "config"
    });
  }
  @override
  onInvoke(Map<String, dynamic> params) async {
    var keys = this.parent.children.keys.toList();
    for (var name in keys) {
      var node = parent.children[name];
      if (node.disconnected != null) {
        (this.provider as DgApiNodeProvider).removeConnection(name);
      }
    };
    saveLink();
    return {};
  }
}