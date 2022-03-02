open Cil
open Common
open Iparsing
open Lexing

let csv_sep = ';'

let print_error_position outx lexbuf =
  let pos = lexbuf.lex_curr_p in
  Printf.fprintf outx "%s:%d:%d" pos.pos_fname
    pos.pos_lnum (pos.pos_cnum - pos.pos_bol + 1)

let parse_exp_with_error lexbuf =
  try Iparser.inv Ilexer.read lexbuf with
  | Ilexer.SyntaxError msg ->
    Printf.fprintf stderr "%a: %s\n" print_error_position lexbuf msg;
    exit (-1)
  | Iparser.Error ->
    Printf.fprintf stderr "%a: syntax error\n" print_error_position lexbuf;
    exit (-1)

class add_inv_for_complex_exp_visitor ast inv_tbl fd = object(self)
  inherit nopCilVisitor

  method private mk_vtrace label loc =
    let fd_vars = fd.sformals @ fd.slocals in
    let params, _ = List.partition (fun vi -> not (is_cil_tmp vi.vname)) fd_vars in
    let vtrace_param_types = L.map (fun vi -> (vi.vname, vi.vtype)) params in
    let vtrace_fun_typ = mk_fun_typ voidType vtrace_param_types in
    let vtrace_name = mk_vtrace_name loc label in
    let vtrace_fd = mk_fundec vtrace_name vtrace_fun_typ in
    let vtrace_global = GFun (vtrace_fd, loc) in
    let () = ast.globals <- [vtrace_global] @ ast.globals in
    let vtrace_args = List.map (fun v -> vi2e v) vtrace_fd.sformals in
    let vtrace_call = mk_Call vtrace_name vtrace_args in
    vtrace_call

  method private find_and_parse_inv ?(if_inv=true) loc label =
    let missing_appx = if if_inv then Cil.zero else Cil.one in
    let vtrace_name = mk_vtrace_name loc label in
    match H.find_opt inv_tbl vtrace_name with
    | None -> missing_appx
    | Some appx ->
      (try parse_exp_with_error (Lexing.from_string appx) with
      | _ -> missing_appx)

  method vstmt (s: stmt) =
    let action s =
      match s.skind with
      | If (if_cond, if_block, else_block, loc) ->
        if is_complex_exp if_cond then
          let if_appx_exp = self#find_and_parse_inv loc vtrace_if_label in
          let else_appx_exp = self#find_and_parse_inv loc vtrace_else_label in
          (* Errormsg.log "if_appx_exp: %a\n" d_exp if_appx_exp; *)
          (* Errormsg.log "else_appx_exp: %a\n" d_exp else_appx_exp; *)
          let if_instr_stmt =
            let else_error_stmt = mkStmt (If (neg if_appx_exp, mk_error_block (), mk_empty_block (), loc)) in
            mkStmt (If (else_appx_exp, mk_error_block (), mkBlock [else_error_stmt], loc)) in
          (* Errormsg.log "if_instr_stmt: %a\n" d_stmt if_instr_stmt; *)
          let else_instr_stmt =
            let else_error_stmt = mkStmt (If (neg else_appx_exp, mk_error_block (), mk_empty_block (), loc)) in
            mkStmt (If (if_appx_exp, mk_error_block (), mkBlock [else_error_stmt], loc)) in
          (* Errormsg.log "else_instr_stmt: %a\n" d_stmt else_instr_stmt; *)
          if_block.bstmts <- [if_instr_stmt] @ if_block.bstmts;
          else_block.bstmts <- [else_instr_stmt] @ else_block.bstmts;
          s
        else s
      | _ -> s
    in
    ChangeDoChildrenPost(s, action)

end

let add_inv_for_complex_exp ast inv_tbl fd _ =
  let visitor = new add_inv_for_complex_exp_visitor ast inv_tbl fd in
  ignore (visitCilFunction (visitor :> nopCilVisitor) fd)

let () = 
  begin
    initCIL();
    Cil.lineDirectiveStyle := None; (* reduce code, remove all junk stuff *)
    Cprint.printLn := false; (* do not print line *)
    (* for Cil to retain &&, ||, ?: instead of transforming them to If stmts *)
    Cil.useLogicalOperators := true;

    let src = Sys.argv.(1) in
    let csv = Sys.argv.(2) in
    let fn = Filename.remove_extension src in
    let ext = Filename.extension src in
    
    let inv_tbl = H.create 10 in
    let () = L.iter (fun str_lst ->
      match str_lst with
      | lbl::inv::[] -> H.add inv_tbl lbl inv
      | _ -> E.s (E.error "Invalid csv row: %s" (S.concat "; " str_lst))
      ) (Csv.load ~separator:csv_sep ~strip:true csv) 
    in
    
    let ast = Frontc.parse src () in
    iterGlobals ast (only_functions (add_inv_for_complex_exp ast inv_tbl));
    (* write_stdout ast *)
    write_src (fn ^ "_validate" ^ ext) ast
  end