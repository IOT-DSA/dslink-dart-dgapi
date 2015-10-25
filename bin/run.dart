import 'dart:async';
import 'package:dslink/dslink.dart';

import '../lib/dgapi.dart';

import 'package:http/http.dart' as http;

bool hasChanged = false;

main(List<String> args) async {
  DgApiNodeProvider provider = new DgApiNodeProvider();
  SimpleNode root = provider.nodes["/"] = new SimpleNode("/");
  provider.nodes["/Add_Connection"] = new AddConnectionNode("/Add_Connection");
  root.addChild("Add_Connection", provider.nodes["/Add_Connection"]);
  link = new LinkProvider(args, "dgapi-", nodeProvider: provider, isResponder: true, autoInitialize: false);
  link.init();

  saveLink = () {
    hasChanged = true;
  };

  Scheduler.every(Interval.FIVE_SECONDS, () async {
    if (hasChanged) {
      hasChanged = false;
      await link.saveAsync();
    }
  });

  int count = 0;

  while (true) {
    count++;
    if (provider.nx == 0 || count == 500 || (provider.nx != -1 && provider.ll == provider.nx)) {
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

  http.Response response = await httpClient.get(host).timeout(const Duration(seconds: 5));

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

    if (response.body.contains("ENVYSION") || response.body.contains("ECLYPSE")) {
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
      r"$invokable": "write",
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

    IOldApiConnection connection = new OldApiBaseAuthConnection(url, user, password);
    await connection.login();
    DgApiNodeProvider provider = link.provider;
    provider.services[name] = connection.service;
    provider.nodes["/"].addChild(name, new SimpleNode("/")..load({
      r"$$dgapi_url": url,
      r"$$dgapi_username": user,
      r"$$dgapi_password": password
    }));
    hasChanged = true;
    return {};
  }
}
