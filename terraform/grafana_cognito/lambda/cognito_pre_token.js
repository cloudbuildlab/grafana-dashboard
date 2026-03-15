exports.handler = function (event, context, callback) {
  var groups = (event.request.groupConfiguration && event.request.groupConfiguration.groupsToOverride) || [];
  var role = '';
  if (groups.indexOf('grafana-admins') !== -1) role = 'Admin';
  else if (groups.indexOf('grafana-editors') !== -1) role = 'Editor';
  else if (groups.indexOf('grafana-viewers') !== -1) role = 'Viewer';
  // Empty string + strict mode in Grafana = login denied for users not in any grafana group.

  event.response = {
    claimsOverrideDetails: {
      claimsToAddOrOverride: { grafana_role: role }
    }
  };
  callback(null, event);
};
