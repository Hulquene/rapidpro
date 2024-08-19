# Generated by Django 5.1 on 2024-08-19 18:37

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("api", "0045_apitoken_last_used_on"),
        ("auth", "0012_alter_user_first_name_max_length"),
    ]

    operations = [
        migrations.AlterField(
            model_name="apitoken",
            name="role",
            field=models.ForeignKey(null=True, on_delete=django.db.models.deletion.PROTECT, to="auth.group"),
        ),
    ]
