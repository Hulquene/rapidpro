# Generated by Django 3.2.9 on 2022-01-06 20:36

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("flows", "0266_auto_20220113_1706"),
    ]

    operations = [
        migrations.AlterField(
            model_name="flowsession",
            name="status",
            field=models.CharField(
                choices=[
                    ("W", "Waiting"),
                    ("C", "Completed"),
                    ("I", "Interrupted"),
                    ("X", "Expired"),
                    ("F", "Failed"),
                ],
                max_length=1,
            ),
        ),
        migrations.AddConstraint(
            model_name="flowsession",
            constraint=models.CheckConstraint(
                check=models.Q(
                    models.Q(("status", "W"), _negated=True),
                    models.Q(("wait_expires_on__isnull", False), ("wait_started_on__isnull", False)),
                    _connector="OR",
                ),
                name="flows_session_waiting_has_started_and_expires",
            ),
        ),
    ]