import QtQml 2.0
import qf.core 1.0
import qf.qmlwidgets 1.0
import "qrc:/qf/core/qml/js/stringext.js" as StringExt
// import Event 1.0
// import Classes 1.0
// import Competitors 1.0

QtObject {
	id: root

	property QfObject internals: QfObject
	{
		SqlConnection {
			id: db
		}
	}

	function whenServerConnected()
	{
		console.debug("whenServerConnected");
		if(FrameWork.plugin("SqlDb").api.sqlServerConnected) {
			var core_feature = FrameWork.plugin("Core");
			var settings = core_feature.api.createSettings();
			settings.beginGroup("sql/connection");
			var event_name = settings.value('event');
			settings.destroy();
			openEvent(event_name);
		}
	}

	function chooseAndImport()
	{
		var d = new Date;
		d.setMonth(d.getMonth() - 1);
		var url = 'http://oris.orientacnisporty.cz/API/?format=json&method=getEventList&sport=1&datefrom=' + d.toISOString().slice(0, 10);
		FrameWork.plugin("Core").api.downloadContent(url, function(get_ok, json_str)
		{
			//Log.info("http get finished:", get_ok, url);
			if(get_ok) {
				var json = JSON.parse(json_str)
				var event_descriptions = []
				var event_ids = []
				for(var event_name in json.Data) {
					var event = json.Data[event_name];
					//Log.info(event.Name)
					event_ids.push(event.ID);
					event_descriptions.push(event.Date + " " + event.Name + (event.Org1? (" " + event.Org1.Abbr): ""));
				}
				var ix = InputDialogSingleton.getItemIndex(null, qsTr('Query'), qsTr('Import event'), event_descriptions, 0, false);
				if(ix >= 0) {
					importEvent(event_ids[ix]);
				}
			}
			else {
                MessageBoxSingleton.critical(FrameWork, "http get error: " + json_str + ' on: ' + url)
			}

		});
	}

	function importEvent(event_id)
	{
		var url = 'http://oris.orientacnisporty.cz/API/?format=json&method=getEvent&id=' + event_id;
		FrameWork.plugin("Core").api.downloadContent(url, function(get_ok, json_str)
		{
			//Log.info("http get finished:", get_ok, url);
			if(get_ok) {
				//Log.info("Imported event:", json_str);
				var event_api = FrameWork.plugin("Event");
                var data = JSON.parse(json_str).Data;
				var stage_count = parseInt(data.Stages);
				if(!stage_count)
					stage_count = 1;
				Log.info("pocet etap:", stage_count);
                var cfg = event_api.eventConfig;
				cfg.setValue('event.stageCount', stage_count);
				cfg.setValue('event.name', data.Name);
				cfg.setValue('event.description', '');
				cfg.setValue('event.date', data.Date);
				cfg.setValue('event.place', data.Place);
				cfg.setValue('event.mainReferee', data.MainReferee.FirstName + ' ' + data.MainReferee.LastName);
				cfg.setValue('event.director', data.Director.FirstName + ' ' + data.Director.LastName);
				cfg.setValue('event.importId', event_id);

				if(!event_api.createEvent("", cfg.values()))
					return;
				//cfg.load();
				var event_name = event_api.eventName;
				if(!event_api.openEvent(event_name))
					return;

				db.transaction();
				var items_processed = 0;
				var items_count = 0;
				for(var class_obj in data.Classes) {
					items_count++;
				}
				var cp = FrameWork.plugin("Classes");
				var class_doc = cp.createClassDocument(root);
				for(var class_obj in data.Classes) {
					var class_id = parseInt(data.Classes[class_obj].ID);
					var class_name = data.Classes[class_obj].Name;
					FrameWork.showProgress("Importing class: " + class_name, items_processed++, items_count);
					Log.info("adding class id:", class_id, "name:", class_name);
					class_doc.loadForInsert();
					class_doc.setValue("id", class_id);
					class_doc.setValue("name", class_name);
					class_doc.save();
					//break;
				}
				db.commit();
				class_doc.destroy();

				importEventOrisRunners(event_id, stage_count)
			}
			else {
				MessageBoxSingleton.critical("http get error: " + json_str + ' on: ' + url)
			}

		});
	}

	function importEventOrisRunners(event_id, stage_count)
	{
		var url = 'http://oris.orientacnisporty.cz/API/?format=json&method=getEventEntries&eventid=' + event_id;
		FrameWork.plugin("Core").api.downloadContent(url, function(get_ok, json_str)
		{
			//Log.info("http get finished:", get_ok, url);
			if(get_ok) {
				var data = JSON.parse(json_str).Data;
				// import competitors
				//FrameWork.showProgress(qsTr("Importing competitors"), 2, steps);
				var items_processed = 0;
				var competitors_count = 0;
				for(var competitor_obj_key in data) {
					competitors_count++;
				}
				db.transaction();
				var cp = FrameWork.plugin("Competitors");
				var competitor_doc = cp.createCompetitorDocument(root);
				for(var competitor_obj_key in data) {
					var competitor_obj = data[competitor_obj_key];
					Log.debug(JSON.stringify(competitor_obj, null, 2));
					Log.info(competitor_obj.ClassDesc, ' ', competitor_obj.LastName, ' ', competitor_obj.FirstName, "classId:", parseInt(competitor_obj.ClassID));
					var siid = parseInt(competitor_obj.SI);
					var note = competitor_obj.Note;
					if(isNaN(siid)) {
						note += ' SI:' + competitor_obj.SI;
						siid = 0;
					}
					if(competitor_obj.RequestedStart) {
						note += ' req. start: ' + competitor_obj.RequestedStart;
					}
					FrameWork.showProgress("Importing: " + competitor_obj.LastName + " " + competitor_obj.FirstName, items_processed, competitors_count);
					competitor_doc.loadForInsert();
					competitor_doc.setValue('classId', parseInt(competitor_obj.ClassID));
					competitor_doc.setValue('siId', siid);
					competitor_doc.setValue('firstName', competitor_obj.FirstName);
					competitor_doc.setValue('lastName', competitor_obj.LastName);
					competitor_doc.setValue('registration', competitor_obj.RegNo);
					competitor_doc.setValue('licence', competitor_obj.Licence);
					competitor_doc.setValue('note', note);
					competitor_doc.setValue('importId', competitor_obj.ID);
					competitor_doc.save();
					//break;
					items_processed++;
				}
				db.commit();
				competitor_doc.destroy();
				FrameWork.showProgress("", 0, 0);
				FrameWork.plugin("Event").reloadDataRequest();
			}
			else {
				MessageBoxSingleton.critical(FrameWork, "http get error: " + json_str + ' on: ' + url)
			}
		});
	}

	function importClubs()
	{
		var url = 'http://oris.orientacnisporty.cz/API/?format=json&method=getCSOSClubList';
		FrameWork.plugin("Core").api.downloadContent(url, function(get_ok, json_str)
		{
			//Log.info("http get finished:", get_ok, url);
			if(get_ok) {
				var data = JSON.parse(json_str).Data;
				// import clubs
				var items_processed = 0;
				var items_count = 0;
				for(var key in data) {
					items_count++;
				}
				FrameWork.showProgress(qsTr("Importing clubs"), 1, items_count);
				db.transaction();
				var q = db.createQuery();
				var ok = true;
				ok = q.exec("DELETE FROM clubs WHERE importId IS NOT NULL");
				if(ok) {
					q.prepare('INSERT INTO clubs (name, abbr, importId) VALUES (:name, :abbr, :importId)');
					for(var obj_key in data) {
						var obj = data[obj_key];
						//Log.debug(JSON.stringify(obj, null, 2));
						Log.info(obj.Abbr, ' ', obj.Name);
						FrameWork.showProgress(obj_key, items_processed, items_count);

						q.bindValue(':abbr', obj.Abbr);
						q.bindValue(':name', obj.Name);
						q.bindValue(':importId', obj.ID);
						if(!q.exec()) {
							ok = false;
							break;
						}

						items_processed++;
					}
				}
				if(ok)
					db.commit();
				else
					db.rollback();
				q.destroy();
				FrameWork.showProgress("", 0, 0);
				//FrameWork.plugin("Event").reloadDataRequest();
			}
			else {
				MessageBoxSingleton.critical(FrameWork, "http get error: " + json_str + ' on: ' + url)
			}
		});
	}

	function importRegistrations()
	{
		var year = new Date().getFullYear();
		var url = 'http://oris.orientacnisporty.cz/API/?format=json&method=getRegistration&sport=1&year=' + year;
		FrameWork.plugin("Core").api.downloadContent(url, function(get_ok, json_str)
		{
			//Log.info("http get finished:", get_ok, url);
			if(get_ok) {
				var data = JSON.parse(json_str).Data;
				// import clubs
				var items_processed = 0;
				var items_count = 0;
				for(var key in data) {
					items_count++;
				}
				FrameWork.showProgress(qsTr("Importing registrations"), 1, items_count);
				db.transaction();
				var q = db.createQuery();
				var ok = true;
				ok = q.exec("DELETE FROM registrations WHERE importId IS NOT NULL");
				if(ok) {
					q.prepare('INSERT INTO registrations (firstName, lastName, registration, licence, clubAbbr, siId, importId) VALUES (:firstName, :lastName, :registration, :licence, :clubAbbr, :siId, :importId)');
					for(var obj_key in data) {
						var obj = data[obj_key];
						//Log.debug(JSON.stringify(obj, null, 2));
						if(items_processed % 100 === 0) {
							Log.info(items_count, obj.RegNo);
							FrameWork.showProgress(obj.RegNo, items_processed, items_count);
						}

						q.bindValue(':firstName', obj.FirstName);
						q.bindValue(':lastName', obj.LastName);
						var reg = obj.RegNo;
						if(reg) {
							q.bindValue(':registration', reg);
							q.bindValue(':clubAbbr', reg.substring(0, 3));
						}
						q.bindValue(':licence', obj.Lic);
						q.bindValue(':siId', obj.SI);
						q.bindValue(':importId', obj.UserID);

						q.bindValue(':abbr', obj.Abbr);
						q.bindValue(':name', obj.Name);
						q.bindValue(':importId', obj.ID);
						if(!q.exec()) {
							ok = false;
							break;
						}

						items_processed++;
					}
				}
				if(ok)
					db.commit();
				else
					db.rollback();
				q.destroy();
				FrameWork.showProgress("", 0, 0);
				//FrameWork.plugin("Event").reloadDataRequest();
			}
			else {
				MessageBoxSingleton.critical(FrameWork, "http get error: " + json_str + ' on: ' + url)
			}
		});
	}

}
