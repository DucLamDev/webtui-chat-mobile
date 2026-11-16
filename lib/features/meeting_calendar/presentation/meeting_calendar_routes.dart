/// Đường dẫn màn chi tiết cuộc họp (`/meetings/<id>?workspaceId=&channelId=`).
String meetingDetailLocation({
  required String workspaceId,
  required String channelId,
  required String meetingId,
}) {
  return Uri(
    path: '/meetings/${Uri.encodeComponent(meetingId)}',
    queryParameters: <String, String>{
      'workspaceId': workspaceId,
      'channelId': channelId,
    },
  ).toString();
}

/// Đường dẫn phòng chat của nhóm gắn cuộc họp.
String meetingGroupChatLocation({
  required String workspaceId,
  required String channelId,
  required String title,
}) {
  return Uri(
    path: '/conversations/${Uri.encodeComponent(channelId)}',
    queryParameters: <String, String>{
      'workspaceId': workspaceId,
      'title': title,
    },
  ).toString();
}
