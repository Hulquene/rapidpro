# Generated by Django 4.2.3 on 2023-09-21 19:45

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("msgs", "0248_msg_optin_alter_msg_msg_type"),
    ]

    operations = [
        migrations.AddField(
            model_name="broadcast",
            name="optin",
            field=models.ForeignKey(null=True, on_delete=django.db.models.deletion.PROTECT, to="msgs.optin"),
        ),
    ]