# Generated by Django 4.2.3 on 2024-03-21 19:09

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("templates", "0024_alter_templatetranslation_comps_as_dict"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="templatetranslation",
            name="comps_as_dict",
        ),
    ]