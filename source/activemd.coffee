fs          = require 'fs-extra'
path        = require 'path'
Showdown    = require 'showdown'

sys         = require 'sys'


CWD = process.cwd()
LIB_PATH = path.dirname(fs.realpathSync(__filename))

STYLE_FILE_NAME = 'activemarkdown-min.css'
SCRIPT_FILE_NAME = 'activemarkdown-min.js'

assembleViewer = (opts) ->
    { input_file_name, inline, markup, local, page_title } = opts



    if inline
        styles  = readLibFile(STYLE_FILE_NAME)
        scripts = readLibFile(SCRIPT_FILE_NAME)
        styles  = "<style>#{ styles }</style>"
        scripts = "<script>#{ scripts }</script>"
    else
        prefix = if local then '' else 'http://activemarkdown.org/viewer/'
        styles  = "<link rel='stylesheet' href='#{ prefix + STYLE_FILE_NAME }'>"
        scripts = "<script src='#{ prefix + SCRIPT_FILE_NAME }'></script>"

    compiled_template = readLibFile('template.js')
    template_fn = Function(compiled_template)

    now = (new Date()).toISOString()

    markup_output = """<!--
            This file was generated by Active Markdown - http://activemarkdown.org

            #{input_file_name} - #{now}
            -->\n
        """

    markup_output += template_fn.call
        page_title  : page_title
        styles      : styles
        script      : scripts
        markup      : markup

    return markup_output



readLibFile = (name) ->
    return fs.readFileSync(path.join(LIB_PATH, name), 'utf-8').toString()



outputCompiledFile = (input_file_name, markup, cmd_options) ->

    html_output = assembleViewer
        input_file_name     : input_file_name
        inline              : cmd_options.inline
        local               : cmd_options.local
        page_title          : cmd_options.title or input_file_name
        markup              : markup

    if process.stdout.isTTY
        path_components = input_file_name.split('.')
        path_components.pop()
        if path_components.length is 0
            path_components.push('output')
        path_components.push('html')
        output_file_path = path_components.join('.')
        output_file_path = path.join(CWD, output_file_path)
        fs.writeFile(output_file_path, html_output, 'utf-8')
        if cmd_options.local
            output_folder   = path.dirname(output_file_path)
            style_source    = path.join(LIB_PATH, STYLE_FILE_NAME)
            script_source   = path.join(LIB_PATH, SCRIPT_FILE_NAME)
            style_output    = path.join(output_folder, STYLE_FILE_NAME)
            script_output   = path.join(output_folder, SCRIPT_FILE_NAME)
            if style_source isnt style_output
                fs.copy style_source, style_output, (err) ->
                    console.log err
            if script_source isnt script_output
                fs.copy script_source, script_output, (err) ->
                    console.log err

    else
        process.stdout.write(html_output)



processMarkdown = (markdown_source) ->
    AMD_PATTERN = /(`?)(!?)\[([$%-\.\w\d\s]*)]{([-\w\d=\.\:,\[\] ]+)}/g
    pure_markdown = markdown_source.replace AMD_PATTERN, (args...) ->
        [
            code_flag
            graph_flag
            text_content
            script_config
        ] = args[1..4]

        if code_flag
            return "`#{ graph_flag }[#{ text_content }]{#{ script_config }}"

        if graph_flag is '!'
            graph_flag = 'data-graph="true"'
        else
            graph_flag = ''

        span = """ <span class="AMDElement" #{graph_flag} data-config="#{script_config}">#{text_content}</span>"""

        return span

    converter = new Showdown.converter
        extensions: ['github', tableExtension]
    markup = converter.makeHtml(pure_markdown)
    return markup



doCompileFile = (options, args) ->

    if process.stdin.isTTY
        input_file_name = args[0]
        source_file = path.join(CWD, input_file_name)
        markdown_source = fs.readFileSync(source_file, 'utf-8')
        markup = processMarkdown(markdown_source)
        outputCompiledFile(input_file_name, markup, options)
    else
        process.stdin.resume()
        process.stdin.setEncoding('utf8')

        markdown_source = ''
        process.stdin.on 'data', (chunk) ->
            markdown_source += chunk

        process.stdin.on 'end', ->
            markup = processMarkdown(markdown_source)
            outputCompiledFile('stdin', markup, options)



doGenerateSample = ->
    sample_content = readLibFile('sample.md')

    if process.stdout.isTTY
        output_file_path = path.join(CWD, 'sample.md')
        if fs.existsSync(output_file_path)
            sys.puts('sample.md already exists')
            process.exit(1)
        sys.puts('Generating sample.md')
        fs.writeFile(output_file_path, sample_content, 'utf-8')
    else
        process.stdout.write(sample_content)



exports.run = (args, options) ->
    if options.sample
        doGenerateSample()
    else
        if args.length is 0
            throw 'Must specify a file'
        doCompileFile(options, args)



# Include the patched table extension that fixes the multiple-table bug
# https://github.com/coreyti/showdown/pull/48
tableExtension = null

`
/*global module:true*/
/*
 * Basic table support with re-entrant parsing, where cell content
 * can also specify markdown.
 *
 * Tables
 * ======
 *
 * | Col 1   | Col 2                                              |
 * |======== |====================================================|
 * |**bold** | ![Valid XHTML] (http://w3.org/Icons/valid-xhtml10) |
 * | Plain   | Value                                              |
 *
 */

(function(){
  var table = function(converter) {
    var tables = {}, style = 'text-align:left;', filter; 
    tables.th = function(header){
      if (header.trim() === "") { return "";}
      var id = header.trim().replace(/ /g, '_').toLowerCase();
      return '<th id="' + id + '" style="'+style+'">' + header + '</th>';
    };
    tables.td = function(cell) {
      return '<td style="'+style+'">' + converter.makeHtml(cell) + '</td>';
    };
    tables.ths = function(){
      var out = "", i = 0, hs = [].slice.apply(arguments);
      for (i;i<hs.length;i+=1) {
        out += tables.th(hs[i]) + '\n';
      }
      return out;
    };
    tables.tds = function(){
      var out = "", i = 0, ds = [].slice.apply(arguments);
      for (i;i<ds.length;i+=1) {
        out += tables.td(ds[i]) + '\n';
      }
      return out;
    };
    tables.thead = function() {
      var out, i = 0, hs = [].slice.apply(arguments);
      out = "<thead>\n";
      out += "<tr>\n";
      out += tables.ths.apply(this, hs);
      out += "</tr>\n";
      out += "</thead>\n";
      return out;
    };
    tables.tr = function() {
      var out, i = 0, cs = [].slice.apply(arguments);
      out = "<tr>\n";
      out += tables.tds.apply(this, cs);
      out += "</tr>\n";
      return out;
    };
    filter = function(text) { 
      var i=0, lines = text.split('\n'), tbl = [], line, hs, rows, out = [];
      for (i; i<lines.length;i+=1) {
        line = lines[i];
        // looks like a table heading
        if (line.trim().match(/^[|]{1}.*[|]{1}$/)) {
          line = line.trim();
          tbl.push('<table>');
          hs = line.substring(1, line.length -1).split('|');
          tbl.push(tables.thead.apply(this, hs));
          line = lines[++i];
          if (!line.trim().match(/^[|]{1}[-=| ]+[|]{1}$/)) {
            // not a table rolling back
            line = lines[--i];
          }
          else {
            line = lines[++i];
            tbl.push('<tbody>');
            while (line.trim().match(/^[|]{1}.*[|]{1}$/)) {
              line = line.trim();
              tbl.push(tables.tr.apply(this, line.substring(1, line.length -1).split('|')));
              line = lines[++i];
            }
            tbl.push('</tbody>');
            tbl.push('</table>');
            // we are done with this table and we move along
            out.push(tbl.join('\n'));
            // reset the table in case there are more in the document
            tbl = [];
            continue;
          }
        }
        out.push(line);
      }             
      return out.join('\n');
    };
    return [
    { 
      type: 'lang', 
      filter: filter
    }
    ];
  };

  // // Client-side export
  // if (typeof window !== 'undefined' && window.Showdown && window.Showdown.extensions) { window.Showdown.extensions.table = table; }
  // // Server-side export
  // if (typeof module !== 'undefined') {
  //   module.exports = table;
  // }
  tableExtension = table;
}());

`