// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'package:dslink/dslink.dart';
import 'dart:io';
import 'dart:convert';

import '../lib/dgapi.dart';

main(List<String> args) async {
  DgApiNodeProvider provider = new DgApiNodeProvider();
  SimpleNode root = provider.nodes["/"] = new SimpleNode("/");
  provider.nodes["/Add_Connection"] = new AddConnectionNode("/Add_Connection");
  root.addChild("Add_Connection", provider.nodes["/Add_Connection"]);
  link = new LinkProvider(args, 'dgapi-', nodeProvider: provider, isResponder: true);
  link.init();

  while (true) {
    if (provider.nx == 0 || (provider.nx != -1 && provider.ll == provider.nx)) {
      link.connect();
      break;
    } else {
      await new Future.delayed(new Duration(milliseconds: 5));
    }
  }
}

LinkProvider link;

class AddConnectionNode extends SimpleNode {
  AddConnectionNode(String path) : super(path) {
    load({
      r"$name": "Add Connection",
      r"$params": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "url",
          "type": "string"
        },
        {
          "name": "username",
          "type": "string"
        },
        {
          "name": "password",
          "type": "string"
        }
      ],
      r"$invokable": "write",
      r"$result": "values"
    }, null);
  }

  @override
  onInvoke(Map<String, dynamic> params) async {
    IOldApiConnection connection = new OldApiBaseAuthConnection(params["url"], params["username"], params["password"]);
    await connection.login();
    DgApiNodeProvider provider =  link.provider;
    provider.services[params["name"]] = connection.service;
    provider.nodes["/"].addChild(params["name"], new SimpleNode("/")..load({
      r"$$dgapi_url": params["url"],
      r"$$dgapi_username": params["username"],
      r"$$dgapi_password": params["password"]
    }, null));
    link.save();
    return {};
  }
}

