-- Generated by collect_sql on 2023-06-08 19:08 UTC

----------------------------------------------------------------------
-- Convenience method to call contact_toggle_system_group with a row
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION
  contact_toggle_system_group(_contact contacts_contact, _group_type CHAR(1), _add BOOLEAN)
RETURNS VOID AS $$
DECLARE
  _group_id INT;
BEGIN
  PERFORM contact_toggle_system_group(_contact.id, _contact.org_id, _group_type, _add);
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Toggle a contact's membership of a system group in their org
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION
  contact_toggle_system_group(_contact_id INT, _org_id INT, _group_type CHAR(1), _add BOOLEAN)
RETURNS VOID AS $$
DECLARE
  _group_id INT;
BEGIN
  -- lookup the group id
  SELECT id INTO STRICT _group_id FROM contacts_contactgroup
  WHERE org_id = _org_id AND group_type = _group_type;
  -- don't do anything if group doesn't exist for some inexplicable reason
  IF _group_id IS NULL THEN
    RETURN;
  END IF;
  IF _add THEN
    BEGIN
      INSERT INTO contacts_contactgroup_contacts (contactgroup_id, contact_id) VALUES (_group_id, _contact_id);
    EXCEPTION WHEN unique_violation THEN
      -- do nothing
    END;
  ELSE
    DELETE FROM contacts_contactgroup_contacts WHERE contactgroup_id = _group_id AND contact_id = _contact_id;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION
  extract_jsonb_keys(_jsonb JSONB)
RETURNS TEXT[] AS $$
BEGIN
  RETURN ARRAY(SELECT * FROM JSONB_OBJECT_KEYS(_jsonb));
END;
$$ IMMUTABLE LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Determines the (mutually exclusive) system label for a broadcast record
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_broadcast_determine_system_label(_broadcast msgs_broadcast) RETURNS CHAR(1) STABLE AS $$
BEGIN
  IF _broadcast.schedule_id IS NOT NULL AND _broadcast.is_active = TRUE THEN
    RETURN 'E';
  END IF;

  RETURN NULL; -- does not match any label
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles DELETE statements on broadcast table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_broadcast_on_delete() RETURNS TRIGGER AS $$
BEGIN
    -- add negative system label counts for all rows that belonged to a system label
    INSERT INTO msgs_systemlabelcount("org_id", "label_type", "count", "is_squashed")
    SELECT org_id, temba_broadcast_determine_system_label(oldtab), -count(*), FALSE FROM oldtab
    WHERE temba_broadcast_determine_system_label(oldtab) IS NOT NULL
    GROUP BY org_id, temba_broadcast_determine_system_label(oldtab);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles INSERT statements on broadcast table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_broadcast_on_insert() RETURNS TRIGGER AS $$
BEGIN
    -- add system label counts for all rows which belong to a system label
    INSERT INTO msgs_systemlabelcount("org_id", "label_type", "count", "is_squashed")
    SELECT org_id, temba_broadcast_determine_system_label(newtab), count(*), FALSE FROM newtab
    WHERE temba_broadcast_determine_system_label(newtab) IS NOT NULL
    GROUP BY org_id, temba_broadcast_determine_system_label(newtab);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles UPDATE statements on broadcast table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_broadcast_on_update() RETURNS TRIGGER AS $$
BEGIN
    -- add negative counts for all old non-null system labels that don't match the new ones
    INSERT INTO msgs_systemlabelcount("org_id", "label_type", "count", "is_squashed")
    SELECT o.org_id, temba_broadcast_determine_system_label(o), -count(*), FALSE FROM oldtab o
    INNER JOIN newtab n ON n.id = o.id
    WHERE temba_broadcast_determine_system_label(o) IS DISTINCT FROM temba_broadcast_determine_system_label(n) AND temba_broadcast_determine_system_label(o) IS NOT NULL
    GROUP BY o.org_id, temba_broadcast_determine_system_label(o);

    -- add counts for all new system labels that don't match the old ones
    INSERT INTO msgs_systemlabelcount("org_id", "label_type", "count", "is_squashed")
    SELECT n.org_id, temba_broadcast_determine_system_label(n), count(*), FALSE FROM newtab n
    INNER JOIN oldtab o ON o.id = n.id
    WHERE temba_broadcast_determine_system_label(o) IS DISTINCT FROM temba_broadcast_determine_system_label(n) AND temba_broadcast_determine_system_label(n) IS NOT NULL
    GROUP BY n.org_id, temba_broadcast_determine_system_label(n);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles deletion of flow runs
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_flowrun_delete() RETURNS TRIGGER AS $$
DECLARE
    p INT;
    _path_json JSONB;
    _path_len INT;
BEGIN
    -- if this is a user delete then remove from results
    IF OLD.delete_from_results THEN
        PERFORM temba_update_category_counts(OLD.flow_id, NULL, OLD.results::json);

        -- nothing more to do if path was empty
        IF OLD.path IS NULL OR OLD.path = '[]' THEN RETURN NULL; END IF;

        -- parse path as JSON
        _path_json := OLD.path::json;
        _path_len := jsonb_array_length(_path_json);

        -- for each step in the path, decrement the path count
        p := 1;
        LOOP
            EXIT WHEN p >= _path_len;

            -- it's possible that steps from old flows don't have exit_uuid
            IF (_path_json->(p-1)->'exit_uuid') IS NOT NULL THEN
                PERFORM temba_insert_flowpathcount(
                    OLD.flow_id,
                    UUID(_path_json->(p-1)->>'exit_uuid'),
                    UUID(_path_json->p->>'node_uuid'),
                    timestamptz(_path_json->p->>'arrived_on'),
                    -1
                );
            END IF;

            p := p + 1;
        END LOOP;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles insertion of flow runs
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_flowrun_insert() RETURNS TRIGGER AS $$
DECLARE
    p INT;
    _path_json JSONB;
    _path_len INT;
BEGIN
    -- nothing to do if path is empty
    IF NEW.path IS NULL OR NEW.path = '[]' THEN RETURN NULL; END IF;

    -- parse path as JSON
    _path_json := NEW.path::json;
    _path_len := jsonb_array_length(_path_json);

    -- for each step in the path, increment the path count, and record a recent run
    p := 1;
    LOOP
        EXIT WHEN p >= _path_len;

        PERFORM temba_insert_flowpathcount(
            NEW.flow_id,
            UUID(_path_json->(p-1)->>'exit_uuid'),
            UUID(_path_json->p->>'node_uuid'),
            timestamptz(_path_json->p->>'arrived_on'),
            1
        );
        p := p + 1;
    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles DELETE statements on flowrun table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_flowrun_on_delete() RETURNS TRIGGER AS $$
BEGIN
    -- add negative status counts for all rows being deleted manually
    INSERT INTO flows_flowrunstatuscount("flow_id", "status", "count", "is_squashed")
    SELECT flow_id, status, -count(*), FALSE FROM oldtab
    WHERE delete_from_results = TRUE GROUP BY flow_id, status;

    -- add negative node counts for any runs sitting at a node
    INSERT INTO flows_flownodecount("flow_id", "node_uuid", "count", "is_squashed")
    SELECT flow_id, current_node_uuid, -count(*), FALSE FROM oldtab
    WHERE status IN ('A', 'W') AND current_node_uuid IS NOT NULL GROUP BY flow_id, current_node_uuid;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles INSERT statements on flowrun table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_flowrun_on_insert() RETURNS TRIGGER AS $$
BEGIN
    -- add status counts for all new status values
    INSERT INTO flows_flowrunstatuscount("flow_id", "status", "count", "is_squashed")
    SELECT flow_id, status, count(*), FALSE FROM newtab GROUP BY flow_id, status;

    -- add start counts for all new start values
    INSERT INTO flows_flowstartcount("start_id", "count", "is_squashed")
    SELECT start_id, count(*), FALSE FROM newtab WHERE start_id IS NOT NULL GROUP BY start_id;

    -- add node counts for all new current node values
    INSERT INTO flows_flownodecount("flow_id", "node_uuid", "count", "is_squashed")
    SELECT flow_id, current_node_uuid, count(*), FALSE FROM newtab
    WHERE status IN ('A', 'W') AND current_node_uuid IS NOT NULL GROUP BY flow_id, current_node_uuid;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles UPDATE statements on flowrun table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_flowrun_on_update() RETURNS TRIGGER AS $$
BEGIN
    -- add negative status counts for all old status values that don't match the new ones
    INSERT INTO flows_flowrunstatuscount("flow_id", "status", "count", "is_squashed")
    SELECT o.flow_id, o.status, -count(*), FALSE FROM oldtab o
    INNER JOIN newtab n ON n.id = o.id
    WHERE o.status != n.status
    GROUP BY o.flow_id, o.status;

    -- add status counts for all new status values that don't match the old ones
    INSERT INTO flows_flowrunstatuscount("flow_id", "status", "count", "is_squashed")
    SELECT n.flow_id, n.status, count(*), FALSE FROM newtab n
    INNER JOIN oldtab o ON o.id = n.id
    WHERE o.status != n.status
    GROUP BY n.flow_id, n.status;

    -- add negative node counts for all old current node values that don't match the new ones
    INSERT INTO flows_flownodecount("flow_id", "node_uuid", "count", "is_squashed")
    SELECT o.flow_id, o.current_node_uuid, -count(*), FALSE FROM oldtab o
    INNER JOIN newtab n ON n.id = o.id
    WHERE o.current_node_uuid IS NOT NULL AND o.current_node_uuid != n.current_node_uuid AND o.status IN ('A', 'W')
    GROUP BY o.flow_id, o.current_node_uuid;

    -- add node counts for all new current node values that don't match the old ones
    INSERT INTO flows_flownodecount("flow_id", "node_uuid", "count", "is_squashed")
    SELECT n.flow_id, n.current_node_uuid, count(*), FALSE FROM newtab n
    INNER JOIN oldtab o ON o.id = n.id
    WHERE n.current_node_uuid IS NOT NULL AND o.current_node_uuid != n.current_node_uuid AND n.status IN ('A', 'W')
    GROUP BY n.flow_id, n.current_node_uuid;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles changes relating to a flow run's path
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_flowrun_path_change() RETURNS TRIGGER AS $$
DECLARE
  p INT;
  _old_path_json JSONB;
  _new_path_json JSONB;
  _old_path_len INT;
  _new_path_len INT;
  _old_last_step_uuid TEXT;
BEGIN
    _old_path_json := COALESCE(OLD.path, '[]')::jsonb;
    _new_path_json := COALESCE(NEW.path, '[]')::jsonb;
    _old_path_len := jsonb_array_length(_old_path_json);
    _new_path_len := jsonb_array_length(_new_path_json);

    -- we don't support rewinding run paths, so the new path must be longer than the old
    IF _new_path_len < _old_path_len THEN RAISE EXCEPTION 'Cannot rewind a flow run path'; END IF;

    -- if we have an old path, find its last step in the new path, and that will be our starting point
    IF _old_path_len > 1 THEN
        _old_last_step_uuid := _old_path_json->(_old_path_len-1)->>'uuid';

        -- old and new paths end with same step so path activity doesn't change
        IF _old_last_step_uuid = _new_path_json->(_new_path_len-1)->>'uuid' THEN
            RETURN NULL;
        END IF;

        p := _new_path_len - 1;
        LOOP
            EXIT WHEN p = 1 OR _new_path_json->(p-1)->>'uuid' = _old_last_step_uuid;
            p := p - 1;
        END LOOP;
    ELSE
        p := 1;
    END IF;

    LOOP
      EXIT WHEN p >= _new_path_len;
      PERFORM temba_insert_flowpathcount(
          NEW.flow_id,
          UUID(_new_path_json->(p-1)->>'exit_uuid'),
          UUID(_new_path_json->p->>'node_uuid'),
          timestamptz(_new_path_json->p->>'arrived_on'),
          1
      );
      p := p + 1;
    END LOOP;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles changes to a run's status
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_flowrun_status_change() RETURNS TRIGGER AS $$
BEGIN
    -- restrict changes
    IF OLD.status NOT IN ('A', 'W') AND NEW.status IN ('A', 'W') THEN RAISE EXCEPTION 'Cannot restart an exited flow run'; END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles changes to a flow session's status
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_flowsession_status_change() RETURNS TRIGGER AS $$
BEGIN
  -- restrict changes
  IF OLD.status != 'W' AND NEW.status = 'W' THEN RAISE EXCEPTION 'Cannot restart an exited flow session'; END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Inserts a new channelcount row with the given values
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_insert_channelcount(_channel_id INTEGER, _count_type VARCHAR(2), _count_day DATE, _count INT) RETURNS VOID AS $$
  BEGIN
    IF _channel_id IS NOT NULL THEN
      INSERT INTO channels_channelcount("channel_id", "count_type", "day", "count", "is_squashed")
        VALUES(_channel_id, _count_type, _count_day, _count, FALSE);
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION temba_insert_flowcategorycount(_flow_id integer, result_key text, _result json, _count integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
  BEGIN
    IF _result->>'category' IS NOT NULL THEN
      INSERT INTO flows_flowcategorycount("flow_id", "node_uuid", "result_key", "result_name", "category_name", "count", "is_squashed")
        VALUES(_flow_id, (_result->>'node_uuid')::uuid, result_key, _result->>'name', _result->>'category', _count, FALSE);
    END IF;
  END;
$function$;

----------------------------------------------------------------------
-- Inserts a new FlowNodeCount
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_insert_flownodecount(_flow_id INTEGER, _node_uuid UUID, _count INTEGER) RETURNS VOID AS $$
  BEGIN
    INSERT INTO flows_flownodecount("flow_id", "node_uuid", "count", "is_squashed")
      VALUES(_flow_id, _node_uuid, _count, FALSE);
  END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Inserts a new flowpathcount
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_insert_flowpathcount(_flow_id INTEGER, _from_uuid UUID, _to_uuid UUID, _period TIMESTAMP WITH TIME ZONE, _count INTEGER) RETURNS VOID AS $$
  BEGIN
    INSERT INTO flows_flowpathcount("flow_id", "from_uuid", "to_uuid", "period", "count", "is_squashed")
      VALUES(_flow_id, _from_uuid, _to_uuid, date_trunc('hour', _period), _count, FALSE);
  END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------
-- Increment or decrement a user label count
---------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_insert_label_count(_label_id INT, _count INT)
RETURNS VOID AS $$
BEGIN
  INSERT INTO msgs_labelcount("label_id", "is_archived", "count", "is_squashed")
  VALUES(_label_id, FALSE, _count, FALSE);
END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------
-- Increment or decrement all of a message's labels
---------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION
  temba_insert_message_label_counts(_msg_id BIGINT, _is_archived BOOLEAN, _count INT)
RETURNS VOID AS $$
BEGIN
  INSERT INTO msgs_labelcount("label_id", "count", "is_archived", "is_squashed")
  SELECT label_id, _count, _is_archived, FALSE FROM msgs_msg_labels WHERE msgs_msg_labels.msg_id = _msg_id;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Inserts a new notificationcount row with the given values
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_insert_notificationcount(_org_id INT, _user_id INT, _count INT) RETURNS VOID AS $$
BEGIN
  INSERT INTO notifications_notificationcount("org_id", "user_id", "count", "is_squashed")
  VALUES(_org_id, _user_id, _count, FALSE);
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Inserts a new assignee ticketcount row with the given values
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_insert_ticketcount_for_assignee(_org_id INTEGER, _assignee_id INTEGER, status CHAR(1), _count INT) RETURNS VOID AS $$
BEGIN
    INSERT INTO tickets_ticketcount("org_id", "scope", "status", "count", "is_squashed")
    VALUES(_org_id, format('assignee:%s', coalesce(_assignee_id, 0)), status, _count, FALSE);
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Inserts a new topic ticketcount row with the given values
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_insert_ticketcount_for_topic(_org_id INTEGER, _topic_id INTEGER, status CHAR(1), _count INT) RETURNS VOID AS $$
BEGIN
    INSERT INTO tickets_ticketcount("org_id", "scope", "status", "count", "is_squashed")
    VALUES(_org_id, format('topic:%s', _topic_id), status, _count, FALSE);
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles DELETE statements on ivr_call table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_ivrcall_on_delete() RETURNS TRIGGER AS $$
BEGIN
    -- add negative count for all rows being deleted manually
    INSERT INTO msgs_systemlabelcount(org_id, label_type, count, is_squashed)
    SELECT org_id, 'C', -count(*), FALSE
    FROM oldtab GROUP BY org_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles INSERT statements on ivr_call table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_ivrcall_on_insert() RETURNS TRIGGER AS $$
BEGIN
    -- add call count for all new rows
    INSERT INTO msgs_systemlabelcount(org_id, label_type, count, is_squashed)
    SELECT org_id, 'C', count(*), FALSE FROM newtab GROUP BY org_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Determines the channel count code for a message
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_msg_determine_channel_count_code(_msg msgs_msg) RETURNS CHAR(2) STABLE AS $$
BEGIN
  IF _msg.direction = 'I' THEN
    IF _msg.msg_type = 'V' THEN RETURN 'IV'; ELSE RETURN 'IM'; END IF;
  ELSE
    IF _msg.msg_type = 'V' THEN RETURN 'OV'; ELSE RETURN 'OM'; END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Determines the (mutually exclusive) system label for a msg record
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_msg_determine_system_label(_msg msgs_msg) RETURNS CHAR(1) STABLE AS $$
BEGIN
  IF _msg.direction = 'I' THEN
    -- incoming IVR messages aren't part of any system labels
    IF _msg.msg_type = 'V' THEN
      RETURN NULL;
    END IF;

    IF _msg.visibility = 'V' AND _msg.status = 'H' AND _msg.flow_id IS NULL THEN
      RETURN 'I';
    ELSIF _msg.visibility = 'V' AND _msg.status = 'H' AND _msg.flow_id IS NOT NULL THEN
      RETURN 'W';
    ELSIF _msg.visibility = 'A'  AND _msg.status = 'H' THEN
      RETURN 'A';
    END IF;
  ELSE
    IF _msg.VISIBILITY = 'V' THEN
      IF _msg.status = 'I' OR _msg.status = 'Q' OR _msg.status = 'E' THEN
        RETURN 'O';
      ELSIF _msg.status = 'W' OR _msg.status = 'S' OR _msg.status = 'D' THEN
        RETURN 'S';
      ELSIF _msg.status = 'F' THEN
        RETURN 'X';
      END IF;
    END IF;
  END IF;

  RETURN NULL; -- might not match any label
END;
$$ LANGUAGE plpgsql;

-----------------------------------------------------------------------
--- Trigger procedure to maintain user label counts
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_msg_labels_on_change() RETURNS TRIGGER AS $$
DECLARE
  is_visible BOOLEAN;
BEGIN
  -- label applied to message
  IF TG_OP = 'INSERT' THEN
    -- is this message visible
    SELECT msgs_msg.visibility = 'V'
    INTO STRICT is_visible FROM msgs_msg
    WHERE msgs_msg.id = NEW.msg_id;

    IF is_visible THEN
      PERFORM temba_insert_label_count(NEW.label_id, 1);
    END IF;

  -- label removed from message
  ELSIF TG_OP = 'DELETE' THEN
    -- is this message visible and why is it being deleted?
    SELECT msgs_msg.visibility = 'V' INTO STRICT is_visible
    FROM msgs_msg WHERE msgs_msg.id = OLD.msg_id;

    IF is_visible THEN
      PERFORM temba_insert_label_count(OLD.label_id, -1);
    END IF;

  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Trigger procedure to update user and system labels on column changes
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_msg_on_change() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    -- prevent illegal message states
    IF NEW.direction = 'I' AND NEW.status NOT IN ('P', 'H') THEN
      RAISE EXCEPTION 'Incoming messages can only be PENDING or HANDLED';
    END IF;
    IF NEW.direction = 'O' AND NEW.visibility = 'A' THEN
      RAISE EXCEPTION 'Outgoing messages cannot be archived';
    END IF;
  END IF;

  -- existing message updated
  IF TG_OP = 'UPDATE' THEN
    -- restrict changes
    IF NEW.direction <> OLD.direction THEN RAISE EXCEPTION 'Cannot change direction on messages'; END IF;
    IF NEW.created_on <> OLD.created_on THEN RAISE EXCEPTION 'Cannot change created_on on messages'; END IF;
    IF NEW.msg_type <> OLD.msg_type THEN RAISE EXCEPTION 'Cannot change msg_type on messages'; END IF;

    -- is being archived or deleted (i.e. no longer included for user labels)
    IF OLD.visibility = 'V' AND NEW.visibility != 'V' THEN
      PERFORM temba_insert_message_label_counts(NEW.id, FALSE, -1);
    END IF;

    -- is being restored (i.e. now included for user labels)
    IF OLD.visibility != 'V' AND NEW.visibility = 'V' THEN
      PERFORM temba_insert_message_label_counts(NEW.id, FALSE, 1);
    END IF;

  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles DELETE statements on msg table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_msg_on_delete() RETURNS TRIGGER AS $$
BEGIN
    -- add negative system label counts for all messages that belonged to a system label
    INSERT INTO msgs_systemlabelcount("org_id", "label_type", "count", "is_squashed")
    SELECT org_id, temba_msg_determine_system_label(oldtab), -count(*), FALSE FROM oldtab
    WHERE temba_msg_determine_system_label(oldtab) IS NOT NULL
    GROUP BY org_id, temba_msg_determine_system_label(oldtab);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles INSERT statements on msg table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_msg_on_insert() RETURNS TRIGGER AS $$
BEGIN
    -- add broadcast counts for all new broadcast values
    INSERT INTO msgs_broadcastmsgcount("broadcast_id", "count", "is_squashed")
    SELECT broadcast_id, count(*), FALSE FROM newtab WHERE broadcast_id IS NOT NULL GROUP BY broadcast_id;

    -- add system label counts for all messages which belong to a system label
    INSERT INTO msgs_systemlabelcount("org_id", "label_type", "count", "is_squashed")
    SELECT org_id, temba_msg_determine_system_label(newtab), count(*), FALSE FROM newtab
    WHERE temba_msg_determine_system_label(newtab) IS NOT NULL
    GROUP BY org_id, temba_msg_determine_system_label(newtab);

    -- add channel counts for all messages with a channel
    INSERT INTO channels_channelcount("channel_id", "count_type", "day", "count", "is_squashed")
    SELECT channel_id, temba_msg_determine_channel_count_code(newtab), created_on::date, count(*), FALSE FROM newtab
    WHERE channel_id IS NOT NULL GROUP BY channel_id, temba_msg_determine_channel_count_code(newtab), created_on::date;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles UPDATE statements on msg table
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_msg_on_update() RETURNS TRIGGER AS $$
BEGIN
    -- add negative counts for all old non-null system labels that don't match the new ones
    INSERT INTO msgs_systemlabelcount("org_id", "label_type", "count", "is_squashed")
    SELECT o.org_id, temba_msg_determine_system_label(o), -count(*), FALSE FROM oldtab o
    INNER JOIN newtab n ON n.id = o.id
    WHERE temba_msg_determine_system_label(o) IS DISTINCT FROM temba_msg_determine_system_label(n) AND temba_msg_determine_system_label(o) IS NOT NULL
    GROUP BY o.org_id, temba_msg_determine_system_label(o);

    -- add counts for all new system labels that don't match the old ones
    INSERT INTO msgs_systemlabelcount("org_id", "label_type", "count", "is_squashed")
    SELECT n.org_id, temba_msg_determine_system_label(n), count(*), FALSE FROM newtab n
    INNER JOIN oldtab o ON o.id = n.id
    WHERE temba_msg_determine_system_label(o) IS DISTINCT FROM temba_msg_determine_system_label(n) AND temba_msg_determine_system_label(n) IS NOT NULL
    GROUP BY n.org_id, temba_msg_determine_system_label(n);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Trigger procedure to notification counts on notification changes
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_notification_on_change() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT NEW.is_seen THEN -- new notification inserted
    PERFORM temba_insert_notificationcount(NEW.org_id, NEW.user_id, 1);
  ELSIF TG_OP = 'UPDATE' THEN -- existing notification updated
    IF OLD.is_seen AND NOT NEW.is_seen THEN -- becoming unseen again
      PERFORM temba_insert_notificationcount(NEW.org_id, NEW.user_id, 1);
    ELSIF NOT OLD.is_seen AND NEW.is_seen THEN -- becoming seen
      PERFORM temba_insert_notificationcount(NEW.org_id, NEW.user_id, -1);
    END IF;
  ELSIF TG_OP = 'DELETE' AND NOT OLD.is_seen THEN -- existing notification deleted
    PERFORM temba_insert_notificationcount(OLD.org_id, OLD.user_id, -1);
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Trigger procedure to update user and system labels on column changes
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_ticket_on_change() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN -- new ticket inserted
    PERFORM temba_insert_ticketcount_for_assignee(NEW.org_id, NEW.assignee_id, NEW.status, 1);
    PERFORM temba_insert_ticketcount_for_topic(NEW.org_id, NEW.topic_id, NEW.status, 1);

    IF NEW.status = 'O' THEN
      UPDATE contacts_contact SET ticket_count = ticket_count + 1, modified_on = NOW() WHERE id = NEW.contact_id;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN -- existing ticket updated
    IF OLD.assignee_id IS DISTINCT FROM NEW.assignee_id OR OLD.status != NEW.status THEN
      PERFORM temba_insert_ticketcount_for_assignee(OLD.org_id, OLD.assignee_id, OLD.status, -1);
      PERFORM temba_insert_ticketcount_for_assignee(NEW.org_id, NEW.assignee_id, NEW.status, 1);
    END IF;

    IF OLD.topic_id != NEW.topic_id OR OLD.status != NEW.status THEN
      PERFORM temba_insert_ticketcount_for_topic(OLD.org_id, OLD.topic_id, OLD.status, -1);
      PERFORM temba_insert_ticketcount_for_topic(NEW.org_id, NEW.topic_id, NEW.status, 1);
    END IF;

    IF OLD.status = 'O' AND NEW.status = 'C' THEN -- ticket closed
      UPDATE contacts_contact SET ticket_count = ticket_count - 1, modified_on = NOW() WHERE id = OLD.contact_id;
    ELSIF OLD.status = 'C' AND NEW.status = 'O' THEN -- ticket reopened
      UPDATE contacts_contact SET ticket_count = ticket_count + 1, modified_on = NOW() WHERE id = OLD.contact_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN -- existing ticket deleted
    PERFORM temba_insert_ticketcount_for_assignee(OLD.org_id, OLD.assignee_id, OLD.status, -1);
    PERFORM temba_insert_ticketcount_for_topic(OLD.org_id, OLD.topic_id, OLD.status, -1);

    IF OLD.status = 'O' THEN -- open ticket deleted
      UPDATE contacts_contact SET ticket_count = ticket_count - 1, modified_on = NOW() WHERE id = OLD.contact_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION temba_update_category_counts(_flow_id integer, new json, old json)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  DECLARE node_uuid text;
  DECLARE result_key text;
  DECLARE result_value text;
  DECLARE value_key text;
  DECLARE value_value text;
  DECLARE _new json;
  DECLARE _old json;
BEGIN
    -- look over the keys in our new results
    FOR result_key, result_value IN SELECT key, value from json_each(new)
    LOOP
        -- if its a new key, create a new count
        IF (old->result_key) IS NULL THEN
            execute temba_insert_flowcategorycount(_flow_id, result_key, new->result_key, 1);
        ELSE
            _new := new->result_key;
            _old := old->result_key;

            IF (_old->>'node_uuid') = (_new->>'node_uuid') THEN
                -- we already have this key, check if the value is newer
                IF timestamptz(_new->>'created_on') > timestamptz(_old->>'created_on') THEN
                    -- found an update to an existing key, create a negative and positive count accordingly
                    execute temba_insert_flowcategorycount(_flow_id, result_key, _old, -1);
                    execute temba_insert_flowcategorycount(_flow_id, result_key, _new, 1);
                END IF;
            ELSE
                -- the parent has changed, out with the old in with the new
                execute temba_insert_flowcategorycount(_flow_id, result_key, _old, -1);
                execute temba_insert_flowcategorycount(_flow_id, result_key, _new, 1);
            END IF;
        END IF;
    END LOOP;

    -- look over keys in our old results that might now be gone
    FOR result_key, result_value IN SELECT key, value from json_each(old)
    LOOP
        IF (new->result_key) IS NULL THEN
            -- found a key that's since been deleted, add a negation
            execute temba_insert_flowcategorycount(_flow_id, result_key, old->result_key, -1);
        END IF;
    END LOOP;
END;
$function$;

----------------------------------------------------------------------
-- Manages keeping track of the # of messages in our channel log
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_update_channellog_count() RETURNS TRIGGER AS $$
BEGIN
  -- ChannelLog being added
  IF TG_OP = 'INSERT' THEN
    -- Error, increment our error count
    IF NEW.is_error THEN
      PERFORM temba_insert_channelcount(NEW.channel_id, 'LE', NULL::date, 1);
    -- Success, increment that count instead
    ELSE
      PERFORM temba_insert_channelcount(NEW.channel_id, 'LS', NULL::date, 1);
    END IF;

  -- Updating is_error is forbidden
  ELSIF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'Cannot update is_error or channel_id on ChannelLog events';

  -- Deleting, decrement our count
  ELSIF TG_OP = 'DELETE' THEN
    -- Error, decrement our error count
    IF OLD.is_error THEN
      PERFORM temba_insert_channelcount(OLD.channel_id, 'LE', NULL::date, -1);
    -- Success, decrement that count instead
    ELSE
      PERFORM temba_insert_channelcount(OLD.channel_id, 'LS', NULL::date, -1);
    END IF;

  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Handles changes to a run's results
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION temba_update_flowcategorycount() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        EXECUTE temba_update_category_counts(NEW.flow_id, NEW.results::json, NULL);
    ELSIF TG_OP = 'UPDATE' THEN
        -- use string comparison to check for no-change case
        IF NEW.results = OLD.results THEN RETURN NULL; END IF;

        EXECUTE temba_update_category_counts(NEW.flow_id, NEW.results::json, OLD.results::json);
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Trigger procedure to update contact system groups on column changes
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_contact_system_groups() RETURNS TRIGGER AS $$
BEGIN
  -- new contact added
  IF TG_OP = 'INSERT' AND NEW.is_active THEN
    IF NEW.status = 'A' THEN
      PERFORM contact_toggle_system_group(NEW, 'A', true);
    ELSIF NEW.status = 'B' THEN
      PERFORM contact_toggle_system_group(NEW, 'B', true);
    ELSIF NEW.status = 'S' THEN
      PERFORM contact_toggle_system_group(NEW, 'S', true);
    ELSIF NEW.status = 'V' THEN
      PERFORM contact_toggle_system_group(NEW, 'V', true);
    END IF;
  END IF;

  -- existing contact updated
  IF TG_OP = 'UPDATE' THEN
    -- do nothing for inactive contacts
    IF NOT OLD.is_active AND NOT NEW.is_active THEN
      RETURN NULL;
    END IF;

    IF OLD.status != NEW.status THEN
      PERFORM contact_toggle_system_group(NEW, OLD.status, false);
      PERFORM contact_toggle_system_group(NEW, NEW.status, true);
    END IF;

    -- is being released
    IF OLD.is_active AND NOT NEW.is_active THEN
      PERFORM contact_toggle_system_group(NEW, 'A', false);
      PERFORM contact_toggle_system_group(NEW, 'B', false);
      PERFORM contact_toggle_system_group(NEW, 'S', false);
      PERFORM contact_toggle_system_group(NEW, 'V', false);
    END IF;

    -- is being unreleased
    IF NOT OLD.is_active AND NEW.is_active THEN
      PERFORM contact_toggle_system_group(NEW, NEW.status, true);
    END IF;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Trigger procedure to update group count
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_group_count() RETURNS TRIGGER AS $$
BEGIN
  -- contact being added to group
  IF TG_OP = 'INSERT' THEN
    INSERT INTO contacts_contactgroupcount("group_id", "count", "is_squashed") VALUES(NEW.contactgroup_id, 1, FALSE);

  -- contact being removed from a group
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO contacts_contactgroupcount("group_id", "count", "is_squashed") VALUES(OLD.contactgroup_id, -1, FALSE);

  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

