part of dglux.dgapi;


class DgApiNodeProvider implements NodeProvider {
  final DGDataService service;
  Map<String, DgApiNode> nodes = new Map<String, DgApiNode>();

  DgApiNodeProvider(this.service);
  LocalNode getNode(String path) {
    if (nodes.containsKey(path)) {
      return nodes[path];
    }
    // don't cache in nodes map, it's only for running subscription
    // other nodes are just used once and throw away
    return new DgApiNode(path, this);
  }
  LocalNode operator [](String path) {
    return getNode(path);
  }
  
  /// register node for subscribe or list api
  void registerNode(DgApiNode node) {
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
}