// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'package:dslink/client.dart';
import 'dart:io';
import 'dart:convert';

import '../lib/dgapi.dart';


//TODO load serverUrl from dslink.json


main(List<String> args) async {
  IOldApiConnection connection = new OldApiBaseAuthConnection('http://rnd.dglogik.net:9999/dglux5/', 'dgSuper','dglux1234');

  await connection.login();

//  connection.service.getNode((node){
//    print(node);
//  }, 'slot:/Training/AHU_4/SAT/Auto', onError:(str){print(str);});
  DgApiNodeProvider nodeProvider = new DgApiNodeProvider(connection.service);
  LinkProvider linkProvider = new LinkProvider(args, 'dgapi-', nodeProvider:nodeProvider, isResponder:true)..connect();
}
