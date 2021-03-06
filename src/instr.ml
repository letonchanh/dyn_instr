open Globals

let main () =
  let _ = Arguments.parse_arguments () in
  if !Globals.enable_dig_instr then
    let _ = print_endline "Instrumentation for dynamic analysis with DIG" in
    Tinstr.vtrace_instr !Globals.input_file ~loop_bnd:!Globals.loop_bnd
  else if !Globals.enable_validate_instr then
    let _ = print_endline "Instrumentation for static validation with Ultimate" in
    Vinstr.validate_instr !Globals.input_file ~csv:!Globals.input_csv_inv_file ~pre:!Globals.input_precond ~case:!Globals.input_case_label
  else if String.length !Globals.input_csv_lia_file > 0 then
    let _ = print_endline "Instrumentation for inserting LIA conditions" in
    Vinstr.lia_instr !Globals.input_file ~csv:!Globals.input_csv_lia_file
  else
    failwith "No option provided!"

let _ =
  let () = Printexc.record_backtrace true in
  try main () with e ->
    let msg = Printexc.to_string e
    and stack = Printexc.get_backtrace () in
    Printf.eprintf "There was an error: %s\n%s\n" msg stack;
    exit 1
;;
  