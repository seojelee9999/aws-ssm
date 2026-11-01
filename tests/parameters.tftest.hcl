# Mocked provider: these tests never contact AWS or create real parameters.
mock_provider "aws" {}

variables {
  parameter_prefix = "/myapp/test"
  parameters = {
    DB_HOST = {
      type = "String"
    }
    DB_PASSWORD = {}
  }
  parameter_values = {
    DB_HOST     = "db.example.invalid"
    DB_PASSWORD = "test-only-value"
  }
}

run "parameter_paths_and_encryption" {
  command = plan

  assert {
    condition     = aws_ssm_parameter.this["DB_PASSWORD"].type == "SecureString"
    error_message = "Parameters must default to SecureString."
  }

  assert {
    condition     = output.parameter_names["DB_HOST"] == "/myapp/test/DB_HOST"
    error_message = "Parameters must be placed under the configured path."
  }
}

run "reject_empty_value" {
  command = plan

  variables {
    parameter_values = {
      DB_HOST     = "db.example.invalid"
      DB_PASSWORD = ""
    }
  }

  expect_failures = [var.parameter_values]
}

run "individual_prefix_and_tags" {
  command = plan

  variables {
    parameters = {
      DB_HOST = { type = "String" }
      DB_PASSWORD = {
        prefix = "/myapp/secrets"
        tags   = { Service = "secrets" }
      }
    }
  }

  assert {
    condition     = output.parameter_names["DB_PASSWORD"] == "/myapp/secrets/DB_PASSWORD" && output.parameter_names["DB_HOST"] == "/myapp/test/DB_HOST"
    error_message = "Per-parameter prefixes must not change other paths."
  }

  assert {
    condition     = aws_ssm_parameter.this["DB_PASSWORD"].tags["Service"] == "secrets"
    error_message = "Per-parameter tags must be applied."
  }
}

run "reject_unlisted_value" {
  command = plan

  variables {
    parameter_values = {
      DB_HOST        = "db.example.invalid"
      DB_PASSWORD    = "test-only-value"
      UNLISTED_VALUE = "must-not-be-uploaded"
    }
  }

  expect_failures = [var.parameter_values]
}

run "reject_missing_value" {
  command = plan

  variables {
    parameter_values = {
      DB_HOST = "db.example.invalid"
    }
  }

  expect_failures = [var.parameter_values]
}

run "reject_noninteger_version" {
  command = plan

  variables {
    parameters = {
      DB_HOST     = { type = "String" }
      DB_PASSWORD = { value_version = 1.5 }
    }
  }

  expect_failures = [var.parameters]
}
