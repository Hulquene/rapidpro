# -*- coding: utf-8 -*-
# Generated by Django 1.11.6 on 2018-06-02 23:16
from __future__ import unicode_literals

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [("contacts", "0080_contactfield_priority")]

    operations = [
        migrations.AlterField(
            model_name="contact",
            name="org",
            field=models.ForeignKey(
                help_text="The organization that this contact belongs to",
                on_delete=django.db.models.deletion.PROTECT,
                related_name="org_contacts",
                to="orgs.Org",
                verbose_name="Org",
            ),
        ),
        migrations.AlterField(
            model_name="contacturn",
            name="channel",
            field=models.ForeignKey(
                blank=True,
                help_text="The preferred channel for this URN",
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                to="channels.Channel",
            ),
        ),
        migrations.AlterField(
            model_name="contacturn",
            name="contact",
            field=models.ForeignKey(
                blank=True,
                help_text="The contact that this URN is for, can be null",
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="urns",
                to="contacts.Contact",
            ),
        ),
        migrations.AlterField(
            model_name="contacturn",
            name="org",
            field=models.ForeignKey(
                help_text="The organization for this URN, can be null",
                on_delete=django.db.models.deletion.PROTECT,
                to="orgs.Org",
            ),
        ),
    ]
