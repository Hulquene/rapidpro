# Generated by Django 4.0.4 on 2022-04-29 15:58

from django.db import migrations, models

import temba.utils.fields


class Migration(migrations.Migration):

    dependencies = [
        ("campaigns", "0045_squashed"),
    ]

    operations = [
        migrations.AlterField(
            model_name="campaign",
            name="name",
            field=models.CharField(max_length=64, validators=[temba.utils.fields.validate_name]),
        ),
    ]
