# -----------------------------------------------------------------------------
# Create Cognito users from var.cognito_users. Each receives a welcome email
# with a temporary password. Terraform adds each user to their group.
# -----------------------------------------------------------------------------

locals {
  # One entry per email so we create each user once; group is the one assigned
  cognito_users_by_email = length(local.flat_cognito_users) > 0 ? {
    for u in local.flat_cognito_users : u.email => u
  } : {}
}

resource "random_password" "cognito_user" {
  for_each = local.cognito_users_by_email

  length  = 16
  special = true
}

resource "aws_cognito_user" "grafana" {
  for_each = local.cognito_users_by_email

  user_pool_id = aws_cognito_user_pool.grafana.id
  username     = each.value.email

  temporary_password       = random_password.cognito_user[each.key].result
  desired_delivery_mediums = ["EMAIL"]

  attributes = merge(
    {
      email          = each.value.email
      email_verified = true
    },
    each.value.name != "" ? { preferred_username = each.value.name } : {}
  )

  depends_on = [
    aws_cognito_user_pool_domain.grafana,
    aws_cognito_user_group.grafana_admins,
    aws_cognito_user_group.grafana_editors,
    aws_cognito_user_group.grafana_viewers,
  ]

  lifecycle {
    ignore_changes = [temporary_password]
  }
}

resource "aws_cognito_user_in_group" "grafana" {
  for_each = length(local.flat_cognito_users) > 0 ? {
    for u in local.flat_cognito_users : "${u.email}-${u.group}" => u
  } : {}

  user_pool_id = aws_cognito_user_pool.grafana.id
  username     = each.value.email
  group_name   = each.value.group

  depends_on = [aws_cognito_user.grafana]
}
