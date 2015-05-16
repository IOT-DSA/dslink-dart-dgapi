part of dglux.dgapi;

typedef void DataCallback(Map data);
typedef void StringCallback(String err);

class QueryToken{
  Function callback;
  StringCallback onError;
  Map meta;
  QueryToken(this.callback, this.onError,[this.meta]);
  void cancel() {
    callback = null;
    onError = null;
  }
  bool get canceled => callback == null;
}


class DGDataService {
  String hostUrl;
  String dataUrl;
  String dbUrl;
  DGDataService(this.hostUrl, this.dataUrl, this.dbUrl) {
    
  }
  
  void addWatch(DataCallback callback, String path) {
    
  }
  void removeWatch(DataCallback callback, String path) {
    
  }
  
  QueryToken invoke(DataCallback callback, String actionName, String path, Map parameters,
                      {bool reuseReq:false, bool table:false, int streamCache:0, StringCallback onError}) {
    
                      }


  QueryToken getHistory(DataCallback callback, String path, String timeRange, String interval, String rollup, {StringCallback onError}) {
    
  }


  QueryToken getChildren(DataCallback callback, String parentPath, {StringCallback onError}) {
    
  }

  QueryToken watchChildren(DataCallback callback, String parentPath, {StringCallback onError}) {
    
  }

  QueryToken getNode(DataCallback callback, String path, {bool noCache:false, StringCallback onError}) {
    
  }
  
}