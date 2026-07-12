#![no_main]
use libfuzzer_sys::fuzz_target;

use libfuzzer_sys::arbitrary::{self, Arbitrary};
use pulldown_cmark::Options;

#[derive(Debug, Arbitrary)]
struct FuzzingInput<'a> {
    markdown: &'a str,
    tables: bool,
    footnotes: bool,
    strikethrough: bool,
    tasklists: bool,
    smart_punctuation: bool,
    heading_attributes: bool,
    yaml_metadata: bool,
    pluses_metadata: bool,
    old_footnotes: bool,
    math: bool,
    gfm: bool,
    definition_list: bool,
    superscript: bool,
    subscript: bool,
    wikilinks: bool,
}

fuzz_target!(|data: FuzzingInput<'_>| {
    let mut opts = Options::empty();

    if data.tables {
        opts.insert(Options::ENABLE_TABLES);
    }
    if data.footnotes {
        opts.insert(Options::ENABLE_FOOTNOTES);
    }
    if data.strikethrough {
        opts.insert(Options::ENABLE_STRIKETHROUGH);
    }
    if data.tasklists {
        opts.insert(Options::ENABLE_TASKLISTS);
    }
    if data.smart_punctuation {
        opts.insert(Options::ENABLE_SMART_PUNCTUATION);
    }
    if data.heading_attributes {
        opts.insert(Options::ENABLE_HEADING_ATTRIBUTES);
    }
    if data.yaml_metadata {
        opts.insert(Options::ENABLE_YAML_STYLE_METADATA_BLOCKS);
    }
    if data.pluses_metadata {
        opts.insert(Options::ENABLE_PLUSES_DELIMITED_METADATA_BLOCKS);
    }
    if data.old_footnotes {
        opts.insert(Options::ENABLE_OLD_FOOTNOTES);
    }
    if data.math {
        opts.insert(Options::ENABLE_MATH);
    }
    if data.gfm {
        opts.insert(Options::ENABLE_GFM);
    }
    if data.definition_list {
        opts.insert(Options::ENABLE_DEFINITION_LIST);
    }
    if data.superscript {
        opts.insert(Options::ENABLE_SUPERSCRIPT);
    }
    if data.subscript {
        opts.insert(Options::ENABLE_SUBSCRIPT);
    }
    if data.wikilinks {
        opts.insert(Options::ENABLE_WIKILINKS);
    }

    let parser = pulldown_cmark::Parser::new_ext(data.markdown, opts);
    let mut html = String::new();
    pulldown_cmark::html::push_html(&mut html, parser);
});
