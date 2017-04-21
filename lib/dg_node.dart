import 'package:dslink/dslink.dart';

class DGNode extends SimpleNode {
  static const String isType = 'dgNode';

  static Map<String, dynamic> def(String ts) => {
    r'$is': isType,
    r'$disconnectedTs': ts
  };

  @override
  String get disconnected => _discoTs;
  String _discoTs;

  DGNode(String path, [SimpleNodeProvider provider]) : super(path, provider) {
    _discoTs = ValueUpdate.getTs();
    load(DGNode.def(_discoTs));
    serializable = false;
  }

  void connected() {
    _discoTs = null;
  }

  void disconnect() {
    _discoTs = ValueUpdate.getTs();
  }
}