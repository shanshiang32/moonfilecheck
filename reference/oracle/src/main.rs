// Thin test adapter around the UNMODIFIED published Rust filecheck 0.5.0.
use filecheck::CheckerBuilder;
use serde_json::{json, Value};
use std::io::{self, Read};

fn run(v: &Value) -> Value {
    let rules = v["rules"].as_str().unwrap();
    let input = v["input"].as_str().unwrap();
    match CheckerBuilder::new().text(rules).map(|b| b.finish()) {
        Ok(c) => match c.check(input, &()) {
            Ok(passed) => json!({"status": if passed {"pass"} else {"fail"}}),
            Err(e) => json!({"status":"error", "message":e.to_string()}),
        },
        Err(e) => json!({"status":"error", "message":e.to_string()}),
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let cases: Vec<Value> = serde_json::from_str(&input).unwrap();
    let results: Vec<Value> = cases.iter().map(run).collect();
    println!("{}", serde_json::to_string(&results).unwrap());
}
