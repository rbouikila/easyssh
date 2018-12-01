/*
* Copyright (c) 2018 Murilo Venturoso
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 3 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Murilo Venturoso <muriloventuroso@gmail.com>
*/

namespace EasySSH {
    public class Item : Granite.Widgets.SourceList.Item {
        private Gtk.Menu host_menu;
        public signal void host_edit_clicked (string name);
        public signal void host_remove_clicked (string name);
        public Item (string name = "") {
            Object (
                name: name
            );
        }
        construct {
            host_menu = new Gtk.Menu ();

            var host_edit = new Gtk.MenuItem.with_label (_("Edit"));
            host_edit.activate.connect (() => {
                host_edit_clicked (name);
            });
            host_menu.append (host_edit);

            var host_remove = new Gtk.MenuItem.with_label (_("Remove"));
            host_remove.activate.connect (() => {
                host_remove_clicked (name);
            });
            host_menu.append (host_remove);

            host_menu.show_all();
        }

        public override Gtk.Menu? get_context_menu () {
            return host_menu;
        }
    }

    public class SourceListView : Gtk.Frame {

        public HostManager hostmanager;
        private Welcome welcome;
        private Gtk.Box box;
        public Granite.Widgets.SourceList source_list;
        public MainWindow window { get; construct; }
        private EasySSH.Settings settings;
        private string encrypt_password;
        private bool should_encrypt_data;
        private bool open_dialog;
        public signal void host_edit_clicked (string name);
        public signal void host_remove_clicked (string name);

        public SourceListView (MainWindow window) {
            Object (window: window);
        }

        construct {
            settings = EasySSH.Settings.get_default ();
            hostmanager = new HostManager();
            encrypt_password = "";
            should_encrypt_data = settings.encrypt_data;
            open_dialog = false;

            var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            welcome = new Welcome();
            box.add(welcome);
            paned.position = 130;

            source_list = new Granite.Widgets.SourceList ();

            /* Double click add connection */
            source_list.button_press_event.connect(() => {

                var n_host = hostmanager.get_host_by_name(source_list.selected.name);
                var n = n_host.notebook;
                var term = new TerminalBox(n_host, n, window);
                var next_tab = n.n_tabs;
                if(Type.from_instance(n.current.page).name() == "EasySSHConnection") {
                    next_tab = 0;
                }
                var n_tab = new Granite.Widgets.Tab (n_host.name + " - " + (next_tab + 1).to_string(), null, term);
                term.tab = n_tab;

                n.insert_tab (n_tab, next_tab);
                if(next_tab == 0) {
                    n.remove_tab(n.current);
                }
                n.current = n_tab;
                window.current_terminal = term.term;
                term.set_selected();
                term.term.grab_focus();
            });

            paned.pack1 (source_list, false, false);
            paned.pack2 (box, true, false);
            paned.set_position(settings.panel_size);
            add (paned);

            /* Size of panel */
            paned.size_allocate.connect(() => {
                if(paned.get_position() != settings.panel_size) {
                    settings.panel_size = paned.get_position();
                }
            });
            load_hosts();
            if(settings.sync_ssh_config == true){
                load_ssh_config ();
            }

            source_list.item_selected.connect ((item) => {
                if(item == null) {
                    return;
                }
                window.current_terminal = null;

                var select_host = hostmanager.get_host_by_name(item.name);
                var notebook = select_host.notebook;
                notebook.hexpand = true;
                if(notebook.n_tabs == 0) {
                    var connect = new Connection(select_host, notebook, window);
                    var tab = new Granite.Widgets.Tab (select_host.name, null, connect);
                    notebook.insert_tab(tab, 0);
                }else if(notebook.n_tabs > 0) {
                    if(Type.from_instance(notebook.current.page).name() == "EasySSHTerminalBox") {
                        var box = (TerminalBox)notebook.current.page;
                        window.current_terminal = (TerminalWidget)box.term;
                        window.current_terminal.grab_focus();
                        box.set_selected();
                        box.remove_badge ();
                    }
                }
                var all_read = true;
                foreach (var g_tab in notebook.tabs) {
                    if(g_tab.icon != null) {
                        all_read = false;
                    }
                }
                if(all_read == true) {
                    item.icon = null;
                }
                clean_box();
                box.add(notebook);

                show_all();
            });
            #if WITH_GPG
            settings.changed.connect(() => {
                if(settings.encrypt_data == true && should_encrypt_data == false){
                    get_password (false);
                }
                if(settings.encrypt_data == false && should_encrypt_data == true){
                    encrypt_password = "";
                }
                if(should_encrypt_data != settings.encrypt_data){
                    should_encrypt_data = settings.encrypt_data;
                    save_hosts ();
                }
            });
            #endif

            show_all();
        }

        public void restore_hosts(string host_name, int qtd) {
            var host = hostmanager.get_host_by_name(host_name);
            if(host == null) {
                return;
            }
            var n = host.notebook;
            for (int i = 0; i < qtd; i++) {
                var term = new TerminalBox(host, n, window);
                var next_tab = n.n_tabs;

                var n_tab = new Granite.Widgets.Tab (host.name + " - " + (next_tab + 1).to_string(), null, term);
                term.tab = n_tab;

                n.insert_tab (n_tab, next_tab);
                n.current = n_tab;
                window.current_terminal = term.term;
                term.set_selected();
                term.term.grab_focus();
            }
        }

        public void restore() {
            if(source_list.selected == null) {
                box.add(welcome);
            } else {
                var host = hostmanager.get_host_by_name(source_list.selected.name);
                if(host == null) {
                    box.add(welcome);
                } else {
                    box.add(host.notebook);
                }

            }
            show_all();
        }

        public void clean_box() {
            var children = box.get_children();
            foreach (Gtk.Widget element in children) {
                box.remove(element);
            }
        }

        private void insert_host(Host host, Granite.Widgets.SourceList.ExpandableItem category) {
            var item = new Item (host.name);
            host.item = item;
            category.add (item);
            var n = host.notebook;
            if(n.n_tabs > 0) {
                var r_tab = n.get_tab_by_index(0);
                n.remove_tab(r_tab);
            }
            n.new_tab_requested.connect (() => {
                var n_host = hostmanager.get_host_by_name(source_list.selected.name);
                var term = new TerminalBox(n_host, n, window);
                var next_tab = n.n_tabs;
                var n_tab = new Granite.Widgets.Tab (n_host.name + " - " + (next_tab + 1).to_string(), null, term);
                term.tab = n_tab;
                n.insert_tab (n_tab, next_tab );
                n.current = n_tab;
                window.current_terminal = term.term;
                term.set_selected();
            });
            n.tab_removed.connect(() => {
                if(n.n_tabs == 0) {
                    var n_host = hostmanager.get_host_by_name(host.name);
                    var n_connect = new Connection(n_host, n, window);
                    var n_tab = new Granite.Widgets.Tab (n_host.name, null, n_connect);
                    n.insert_tab(n_tab, 0);
                    window.current_terminal = null;
                }
            });
            n.tab_moved.connect(on_tab_moved);
            n.tab_switched.connect(on_tab_switched);
            item.host_edit_clicked.connect ((name) => {host_edit_clicked (name);});
            item.host_remove_clicked.connect ((name) => {host_remove_clicked (name);});

        }

        private void on_tab_moved (Granite.Widgets.Tab tab, int x, int y) {
            var t = get_term_widget (tab);
            var box = (TerminalBox)tab.page;
            window.current_terminal = t;
            box.set_selected();
            box.remove_badge ();
        }
        private void on_tab_switched (Granite.Widgets.Tab? old_tab, Granite.Widgets.Tab new_tab) {
            if(Type.from_instance(new_tab.page).name() == "EasySSHTerminalBox") {
                var t = get_term_widget (new_tab);
                window.current_terminal = t;
                var box = (TerminalBox)new_tab.page;
                box.set_selected();
                box.remove_badge ();
                box.dataHost.item.icon = null;
                new_tab.icon = null;
                var all_read = true;
                foreach (var g_tab in box.dataHost.notebook.tabs) {
                    if(g_tab.icon != null) {
                        all_read = false;
                    }
                }
                if(all_read == true) {
                    box.dataHost.item.icon = null;
                }
            }
        }
        private TerminalWidget get_term_widget (Granite.Widgets.Tab tab) {
            return (TerminalWidget)((TerminalBox)tab.page).term;
        }
        #if WITH_GPG
        public string get_password(bool unlock) {
            if(open_dialog == true){
                return "";
            }
            open_dialog = true;
            string password;
            if(encrypt_password == ""){
                var description = "";
                if(unlock == true){
                    description = _("Please enter the password to unlock the data file");
                }else{
                    description = _("Please enter the password to lock the data file");
                }
                var message_dialog = new Granite.MessageDialog.with_image_from_icon_name (_("Password"), description, "dialog-password", Gtk.ButtonsType.NONE);
                var password_entry = new Gtk.Entry ();
                password_entry.visibility = false;
                password_entry.show ();
                password_entry.set_activates_default(true);
                message_dialog.custom_bin.add(password_entry);
                var no_button = new Gtk.Button.with_label (_("Cancel"));
                message_dialog.add_action_widget (no_button, Gtk.ResponseType.CANCEL);

                var yes_button = new Gtk.Button.with_label (_("Send"));
                yes_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                yes_button.can_default = true;
                message_dialog.add_action_widget (yes_button, Gtk.ResponseType.OK);
                message_dialog.set_default_response(Gtk.ResponseType.OK);
                message_dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG);
                message_dialog.show_all ();
                if (message_dialog.run () == Gtk.ResponseType.OK) {
                    password = password_entry.text;
                } else {
                    password = "";
                }
                message_dialog.destroy ();
                encrypt_password = password;

            } else {
                password = encrypt_password;
            }
            open_dialog = false;
            return password;
        }

        public string decrypt_data(string password, string path) {
            string output, stderr  = "";
            int exit_status = 0;
            try {
                var cmd = "gpg --batch --yes --quiet --passphrase " + password + " -d '" + path + "'";
                Process.spawn_command_line_sync (cmd, out output, out stderr, out exit_status);
            } catch (Error e) {
                critical (e.message);
            }
            return output;
        }

        public string encrypt_data(string password, string content) {
            string output, stderr  = "";
            int exit_status = 0;
            try {
                var cmd = "sh -c 'echo \"" + content.replace("\"", "\\\"") + "\" | gpg --batch --symmetric --armor --passphrase " + password + "'";
                Process.spawn_command_line_sync (cmd, out output, out stderr, out exit_status);
            } catch (Error e) {
                critical (e.message);
            }
            return output;
        }
        #endif
        public void load_hosts() {
            try {
                string res = "";
                string hosts_folder = EasySSH.settings.hosts_folder.replace ("%20", " ");
                string file_name = "/hosts.json";
                #if WITH_GPG
                if(EasySSH.settings.encrypt_data == true){
                    file_name = "/hosts.json.gpg";
                }
                #endif
                var file = File.new_for_path (hosts_folder + file_name);
                if (!file.query_exists ()) {
                    file.make_directory();
                } else {
                    #if WITH_GPG
                    if(EasySSH.settings.encrypt_data == true){
                        var password = get_password (true);
                        if(password == ""){
                            return;
                        }
                        res = decrypt_data (password, hosts_folder + file_name);
                    } else {
                        string line;
                        var dis = new DataInputStream (file.read ());
                        while ((line = dis.read_line (null)) != null) {
                            res += line;
                        }
                    }
                    #else
                    string line;
                    var dis = new DataInputStream (file.read ());
                    while ((line = dis.read_line (null)) != null) {
                        res += line;
                    }
                    #endif
                    var parser = new Json.Parser ();
                    parser.load_from_data (res);

                    var root_object = parser.get_root ();
                    var json_hosts = root_object.get_array();
                    foreach (var hostnode in json_hosts.get_elements ()) {
                        var item = hostnode.get_object ();
                        var host = new Host();
                        host.name = item.get_string_member("name");
                        if(item.has_member("host")){
                            host.host = item.get_string_member("host");
                        }
                        if(item.has_member("port")){
                            host.port = item.get_string_member("port");
                        }
                        if(item.has_member("username")){
                            host.username = item.get_string_member("username");
                        }

                        host.ssh_config = "";

                        if(item.has_member("password")){
                            host.password = item.get_string_member("password");
                        }
                        if(item.has_member("identity-file")){
                            host.identity_file = item.get_string_member("identity-file");
                        }
                        host.group = item.get_string_member("group");
                        if(item.has_member("color")){
                            host.color = item.get_string_member("color");
                        }else {
                            host.color = EasySSH.settings.terminal_background_color;
                        }
                        if(item.has_member("tunnels")){
                            host.tunnels = item.get_string_member("tunnels");
                        }else {
                            host.tunnels = "";
                        }
                        if(item.has_member("font")){
                            host.font = item.get_string_member("font");
                        }else {
                            host.font = EasySSH.settings.terminal_font;
                        }
                        var group_exist = hostmanager.exist_group(host.group);
                        if(group_exist == false) {
                            var group = add_group(host.group);
                            group.add_host(host);
                        } else {
                            Group group = hostmanager.get_group_by_name(host.group);
                            group.add_host(host);
                        }
                    }

                    foreach(var group in hostmanager.get_groups()) {
                        group.sort_hosts();
                        foreach (var host in group.get_hosts()) {
                            insert_host(host, group.category);
                        }
                    }
                }
            } catch (Error e) {
                stderr.printf ("%s\n", e.message);
            }
        }

        public Host add_host(Host host) {
            var group = hostmanager.get_group_by_name(host.group);
            if(group == null) {
                group = add_group(host.group);
            }
            group.add_host(host);
            insert_host(host, group.category);
            save_hosts();
            return host;
        }

        public Group add_group(string name) {
            var group = new Group(name);
            var category = new Granite.Widgets.SourceList.ExpandableItem (group.name);
            category.expand_all ();
            source_list.root.add (category);
            group.category = category;
            hostmanager.add_group(group);
            return group;
        }

        public Host edit_host(string old_name, Host e_host) {
            var host = hostmanager.get_host_by_name(old_name);
            var group = hostmanager.get_group_by_name(host.group);
            e_host.notebook = host.notebook;
            if(host.group == e_host.group) {
                group.update_host(old_name, e_host);
                host.item.name = e_host.name;
            } else {
                group.category.remove(host.item);
                group.remove_host(host.name);
                var n_group = hostmanager.get_group_by_name(e_host.group);
                if(n_group == null) {
                    n_group = add_group(e_host.group);
                }
                n_group.add_host(e_host);
                insert_host(e_host, n_group.category);
            }
            if(e_host.notebook.n_tabs > 0){
                var tab = e_host.notebook.get_tab_by_index(0);
                if(Type.from_instance(tab.page).name() == "EasySSHConnection") {
                    e_host.notebook.remove_tab(tab);
                    host.item = source_list.selected;
                    source_list.selected = null;
                    clean_box ();
                    box.add (welcome);
                } else {
                    for(int i = 0; i < e_host.notebook.n_tabs; i++) {
                        var l_tab = e_host.notebook.get_tab_by_index(i);
                        if(Type.from_instance(tab.page).name() == "EasySSHTerminalBox") {
                            l_tab.label = e_host.name + " - " + (i + 1).to_string();
                        }
                    }
                }
            } else {
                clean_box ();
                box.add (welcome);
            }

            save_hosts();

            return host;

        }

        public void save_hosts() {
            Json.Array array_hosts = new Json.Array();
            var groups = hostmanager.get_groups();
            var data_ssh_config = "";
            for(int a = 0; a < groups.length; a++) {
                var hosts = groups[a].get_hosts();
                var length_hosts = groups[a].get_length();
                for(int i = 0; i < length_hosts; i++) {
                    if(hosts[i] == null) {
                        continue;
                    }
                    var s_host = new Host();
                    s_host.name = hosts[i].name;
                    s_host.group = hosts[i].group;
                    s_host.host = hosts[i].host;
                    s_host.port = hosts[i].port;
                    s_host.username = hosts[i].username;
                    s_host.password = hosts[i].password;
                    s_host.identity_file = hosts[i].identity_file;
                    s_host.notebook = null;
                    s_host.color = hosts[i].color;
                    s_host.font = hosts[i].font;
                    s_host.tunnels = hosts[i].tunnels;

                    Json.Node root = Json.gobject_serialize(s_host);
                    array_hosts.add_element(root);

                    if(settings.sync_ssh_config){
                        data_ssh_config += "Host " + hosts[i].name.replace(",", " ") + "\n    ";
                        if(hosts[i].ssh_config != ""){
                            data_ssh_config += hosts[i].ssh_config.replace("\n", "\n    ");
                        }else{
                            if(hosts[i].host != ""){
                                data_ssh_config += "HostName " + hosts[i].host + "\n";
                            }
                            if(hosts[i].username != ""){
                                data_ssh_config += "    User " + hosts[i].username + "\n";
                            }
                            if(hosts[i].port != ""){
                                data_ssh_config += "    Port " + hosts[i].port + "\n";
                            }
                            if(hosts[i].identity_file != "" && hosts[i].identity_file != null){
                                data_ssh_config += "    IdentityFile " + hosts[i].identity_file + "\n";
                            }
                        }
                        data_ssh_config += "\n";
                    }
                }
            }

            Json.Node root = new Json.Node.alloc();
            root.init_array(array_hosts);
            Json.Generator gen = new Json.Generator();
            gen.set_root(root);
            string data = gen.to_data(null);
            var filename = "/hosts.json";
            #if WITH_GPG
            if(EasySSH.settings.encrypt_data == true){
                filename = filename + ".gpg";
                var password = get_password (false);
                data = encrypt_data (password, data);
            }
            #endif
            var file = File.new_for_path (EasySSH.settings.hosts_folder.replace ("%20", " ") + filename);
            {
                if (file.query_exists ()) {
                    file.delete ();
                } else {
                    file.make_directory();
                }
                var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));

                dos.put_string (data);
            }

            if(settings.sync_ssh_config){
                var file_ssh = File.new_for_path (Environment.get_home_dir () + "/.ssh/config");
                {
                    if (file_ssh.query_exists ()) {
                        file_ssh.delete ();
                    } else {
                        file_ssh.make_directory();
                    }
                    var dos_ssh = new DataOutputStream (file_ssh.create (FileCreateFlags.REPLACE_DESTINATION));
                    dos_ssh.put_string (data_ssh_config);
                }
            }
        }

        public void load_ssh_config() {

            var file = FileStream.open(Environment.get_home_dir () + "/.ssh/config", "r");
            if (file != null){
                return;
            };

            string line = file.read_line();
            while (line != null){
                var next_line = true;
                if(line.length >= 4 && line.substring(0, 4) == "Host"){

                    var split = line.split(" ");
                    var name_host = split[1];
                    if(split.length > 1){
                        for (int a = 2; a < split.length; a++) {
                            name_host += "," + split[a];
                        }
                    }
                    var host = hostmanager.get_host_by_name(name_host);
                    if(host == null){
                        var n_host = new Host();
                        var result = "";
                        while (line != null) {
                            line = file.read_line();
                            if(line == null){
                                continue;
                            }
                            if(line.length >= 4 && line.substring(0, 4) != "Host"){
                                var l = line.strip();
                                if(l != ""){
                                    result += l + "\n";
                                }
                                if(l.contains ("=")){
                                    l = l.replace("=", "");
                                }
                                if(l.contains (" ")){
                                    var k = l.split(" ")[0];
                                    var v = l.split(" ")[1];
                                    if(k == "HostName"){
                                        n_host.host = v;
                                    }else if (k == "User") {
                                        n_host.username = v;
                                    }else if(k == "Port"){
                                        n_host.port = v;
                                    }else if(k == "IdentityFile"){
                                        n_host.identity_file = v;
                                    }
                                }
                            }else{
                                next_line = false;
                                break;
                            }
                        }
                        n_host.name = name_host;
                        n_host.ssh_config = result;
                        n_host.group = "SSHConfig";
                        add_host(n_host);
                    }else{

                        var result = "";
                        while (line != null) {
                            line = file.read_line();
                            if(line == null){
                                continue;
                            }
                            if(line.length >= 4 && line.substring(0, 4) != "Host"){
                                var l = line.strip();
                                if(l != ""){
                                    result += l.strip() + "\n";
                                }
                                if(l.contains ("=")){
                                    l = l.replace("=", "");
                                }
                                if(l.contains (" ")){
                                    var k = l.split(" ")[0];
                                    var v = l.split(" ")[1];
                                    if(k == "HostName"){
                                        host.host = v;
                                    }else if (k == "User") {
                                        host.username = v;
                                    }else if(k == "Port"){
                                        host.port = v;
                                    }else if(k == "IdentityFile"){
                                        host.identity_file = v;
                                    }
                                }
                            }else{
                                next_line = false;
                                break;
                            }
                        }
                        host.ssh_config = result;
                        hostmanager.update_host (name_host, host);
                    }
                }
                if(next_line){
                    line = file.read_line();
                }
            }
        }

        public string get_host_ssh_config (string name) {

            var file = FileStream.open(Environment.get_home_dir () + "/.ssh/config", "r");
            assert (file != null);
            string line = file.read_line();
            var result = "";
            while (line != null){
                if(line.length >= 4 && line.substring(0, 4) == "Host"){
                    var split = line.split(" ");
                    var name_host = split[1];
                    if(split.length > 1){
                        for (int a = 2; a < split.length; a++) {
                            name_host += "," + split[a];
                        }
                    }
                    if(name_host == name){
                        while (line != null) {
                            line = file.read_line();
                            if(line == null){
                                continue;
                            }
                            if(line.length >= 4 && line.substring(0, 4) != "Host"){
                                var l = line.strip();
                                if(l != ""){
                                    result += l + "\n";
                                }
                            }else{
                                break;
                            }
                        }
                    }
                }
                line = file.read_line();
            }
            return result;
        }

        public void new_conn() {
            clean_box();
            box.add(new ConnectionEditor(this, null));

            show_all();
        }

        public void edit_conn(string name) {
            clean_box();
            var host = hostmanager.get_host_by_name(name);

            box.add(new ConnectionEditor(this, host));
            show_all();
        }
        public void remove_conn(string name) {
            var host = hostmanager.get_host_by_name(name);
            confirm_remove_dialog (host);
        }
        private void confirm_remove_dialog (Host host) {
            var message_dialog = new Granite.MessageDialog.with_image_from_icon_name (_("Remove ") + host.name, _("Are you sure you want to remove this connection and all data associated with it?"), "dialog-warning", Gtk.ButtonsType.CANCEL);
            message_dialog.transient_for = window;
            var suggested_button = new Gtk.Button.with_label (_("Remove"));
            suggested_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
            message_dialog.add_action_widget (suggested_button, Gtk.ResponseType.ACCEPT);

            message_dialog.show_all ();
            if (message_dialog.run () == Gtk.ResponseType.ACCEPT) {
                var group = hostmanager.get_group_by_name(host.group);
                group.category.remove(host.item);
                host.notebook.destroy();
                group.remove_host(host.name);
                save_hosts();
                restore();
            }
            message_dialog.destroy ();
        }
    }
}