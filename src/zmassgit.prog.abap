********************************************************************************
* The MIT License (MIT)
*
* Copyright (c) 2019 abapGit Contributors
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
********************************************************************************
*( )_( )
*(='.'=)
*(")_(")
* This program allow to generate Abapgit ZIP files from transport request(s)
* in a given folder with the given logic ( FULL or PREFIX )


REPORT zmassgit.

*================================ CLASSES =============================*

*============================  MATCHCODES =============================*
CLASS lcl_matchcodes DEFINITION FINAL.

  PUBLIC SECTION.
    CLASS-METHODS f4_folder CHANGING cv_folder TYPE string.
    CLASS-METHODS f4_transport_request CHANGING cv_trkorr TYPE e070v-trkorr.

  PRIVATE SECTION.
    CLASS-DATA: gv_last_folder TYPE string.

ENDCLASS.

CLASS lcl_matchcodes IMPLEMENTATION.

  METHOD f4_folder.

    DATA: lv_folder TYPE string,
          lv_title  TYPE string.

    lv_title = 'Choose the destination folder for the ZIP files '(t01).

    CALL METHOD cl_gui_frontend_services=>directory_browse
      EXPORTING
        window_title         = lv_title
        initial_folder       = gv_last_folder
      CHANGING
        selected_folder      = lv_folder
      EXCEPTIONS
        cntl_error           = 1
        error_no_gui         = 2
        not_supported_by_gui = 3
        OTHERS               = 4.

    IF sy-subrc EQ 0.

      IF lv_folder IS NOT INITIAL.

        cv_folder      = lv_folder.
        gv_last_folder = lv_folder. "Store the last directory for user friendly UI

      ELSE.

        cv_folder = gv_last_folder.

      ENDIF.

    ENDIF.

  ENDMETHOD.

  METHOD f4_transport_request.

    CALL FUNCTION 'TR_F4_REQUESTS'
      IMPORTING
        ev_selected_request = cv_trkorr.

  ENDMETHOD.

ENDCLASS.

*========================== DATA SELECTOR =============================*
CLASS lcl_data_selector DEFINITION FINAL.

  PUBLIC SECTION.

* Transport requests structure
    TYPES: BEGIN OF ty_trkorr,
             trkorr  TYPE e070v-trkorr,
             as4text TYPE e070v-as4text,
           END OF ty_trkorr.

* Transport request extraction table type
    TYPES tt_trkorr TYPE SORTED TABLE OF ty_trkorr WITH UNIQUE KEY trkorr.

* Range of transport request
    TYPES tt_r_trkorr TYPE RANGE OF ty_trkorr-trkorr.

* Selection criterias (match selection screen criterias of transport requests )
    TYPES: BEGIN OF ty_sel_criterias,
             t_r_trkorr TYPE tt_r_trkorr,
           END OF ty_sel_criterias.

    CLASS-DATA:
* Static variable for selection screen
      gv_trkorr TYPE ty_trkorr-trkorr.

* Extract transport requests from E070V
    CLASS-METHODS get_transport_requests IMPORTING is_sel_crit      TYPE ty_sel_criterias
                                         RETURNING VALUE(rt_trkorr) TYPE tt_trkorr.

ENDCLASS.

CLASS lcl_data_selector IMPLEMENTATION.

  METHOD get_transport_requests.

    SELECT trkorr as4text
      FROM e070v
      INTO TABLE rt_trkorr
      WHERE trkorr IN is_sel_crit-t_r_trkorr.
    IF sy-subrc <> 0.
      CLEAR rt_trkorr.
    ENDIF.

  ENDMETHOD.

ENDCLASS.

*========================== REPORTER =============================*
CLASS lcl_reporter DEFINITION FINAL.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_report,
             trkorr   TYPE e070v-trkorr,
             filename TYPE string,
           END OF ty_report.

    TYPES tt_report TYPE STANDARD TABLE OF ty_report.

    METHODS fill_report_table IMPORTING is_trkorr   TYPE lcl_data_selector=>ty_trkorr
                                        iv_filename TYPE ty_report-filename.

    METHODS display_report.

  PRIVATE SECTION.

    DATA gt_report TYPE tt_report.

ENDCLASS.

CLASS lcl_reporter IMPLEMENTATION.

  METHOD fill_report_table.

    DATA: ls_report TYPE ty_report.

    ls_report-trkorr   = is_trkorr-trkorr.
    ls_report-filename = iv_filename.
    APPEND ls_report TO me->gt_report.

  ENDMETHOD.

  METHOD display_report.

    DATA: lo_alv    TYPE REF TO cl_salv_table,
          lo_except TYPE REF TO cx_root.

    TRY.
        CALL METHOD cl_salv_table=>factory "get SALV factory instance
          EXPORTING
            list_display = if_salv_c_bool_sap=>false
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = me->gt_report.

      CATCH cx_salv_msg INTO lo_except.

        MESSAGE lo_except->get_text( ) TYPE 'E'.

    ENDTRY.

    lo_alv->get_columns( )->set_optimize( abap_true ).

    lo_alv->set_screen_status( pfstatus      = 'STANDARD'
                               report        = 'SAPLSALV'
                               set_functions = lo_alv->c_functions_all ).

    lo_alv->display( ). "display grid

  ENDMETHOD.

ENDCLASS.


*=================== TRANSPORT ZIPPER =============================*
CLASS lcl_transport_zipper DEFINITION FINAL.

  PUBLIC SECTION.
* Folder
    TYPES ty_folder TYPE string.
* Logic
    TYPES ty_logic TYPE string.
* Filename
    TYPES ty_filename TYPE fb_icrc_pfile.
* Default logic
    CONSTANTS gc_logic_full(4) TYPE c VALUE 'FULL'.
* File extension
    CONSTANTS gc_zip_ext TYPE string VALUE '.zip' ##NO_TEXT.

    DATA: gv_timestamp   TYPE string,
          gv_full_folder TYPE ty_folder.

    METHODS constructor  IMPORTING iv_folder   TYPE ty_folder
                                   io_reporter TYPE REF TO lcl_reporter
                         RAISING   cx_wrong_data.

    METHODS generate_files IMPORTING it_trkorr TYPE lcl_data_selector=>tt_trkorr
                                     iv_logic  TYPE any
                           RAISING   zcx_abapgit_exception.

    CLASS-METHODS does_folder_exist IMPORTING iv_folder              TYPE string
                                    RETURNING VALUE(rv_folder_exist) TYPE abap_bool
                                    RAISING   cx_wrong_data.

  PRIVATE SECTION.

    DATA: go_reporter TYPE REF TO lcl_reporter.

    METHODS get_full_folder IMPORTING iv_folder             TYPE ty_folder
                            RETURNING VALUE(rv_full_folder) TYPE ty_folder
                            RAISING   cx_wrong_data.

    METHODS save_binstring IMPORTING is_trkorr    TYPE lcl_data_selector=>ty_trkorr
                                     iv_binstring TYPE xstring
                           RAISING   zcx_abapgit_exception.

ENDCLASS.

CLASS lcl_transport_zipper IMPLEMENTATION.

  METHOD constructor.

    CONCATENATE sy-datlo sy-timlo INTO me->gv_timestamp SEPARATED BY '_'.

    me->gv_full_folder = get_full_folder( EXPORTING iv_folder = iv_folder ).

    me->go_reporter = io_reporter.

  ENDMETHOD.

  METHOD does_folder_exist.

    cl_gui_frontend_services=>directory_exist(
      EXPORTING
        directory            = iv_folder
      RECEIVING
        result               = rv_folder_exist
      EXCEPTIONS
        cntl_error           = 1
        error_no_gui         = 2
        wrong_parameter      = 3
        not_supported_by_gui = 4
        OTHERS               = 5
    ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_wrong_data
        MESSAGE e137(c$) WITH 'Internal error checking existence of folder'(m01) iv_folder.
    ENDIF.

  ENDMETHOD.

  METHOD get_full_folder.

    DATA: lv_does_folder_exists TYPE flag,
          lv_sep                TYPE c,
          lv_rc                 TYPE i.

*-obtain file separator character---------------------------------------
    CALL METHOD cl_gui_frontend_services=>get_file_separator
      CHANGING
        file_separator       = lv_sep
      EXCEPTIONS
        cntl_error           = 1
        error_no_gui         = 2
        not_supported_by_gui = 3
        OTHERS               = 4.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_wrong_data
        MESSAGE e137(c$) WITH 'Internal error getting file separator'(m03).
    ENDIF.

    CONCATENATE iv_folder
                gv_timestamp
           INTO rv_full_folder SEPARATED BY lv_sep.

    IF does_folder_exist( EXPORTING iv_folder = rv_full_folder ) = abap_false.

      cl_gui_frontend_services=>directory_create(
        EXPORTING
          directory                = rv_full_folder
        CHANGING
          rc                       = lv_rc    " Return Code
        EXCEPTIONS
          directory_create_failed  = 1
          cntl_error               = 2
          error_no_gui             = 3
          directory_access_denied  = 4
          directory_already_exists = 5
          path_not_found           = 6
          unknown_error            = 7
          not_supported_by_gui     = 8
          wrong_parameter          = 9
          OTHERS                   = 10
      ).
      IF sy-subrc <> 0 AND sy-subrc <> 5.

        RAISE EXCEPTION TYPE cx_wrong_data
          MESSAGE e137(c$) WITH 'Could not create folder'(m02) rv_full_folder.
      ENDIF.

    ENDIF.

  ENDMETHOD.

  METHOD save_binstring.

    DATA: lv_filename TYPE lcl_transport_zipper=>ty_filename.

    DATA:
      lt_rawdata  TYPE solix_tab.

* Generate filename
    CONCATENATE is_trkorr-trkorr '_' is_trkorr-as4text '_' gv_timestamp gc_zip_ext
    INTO lv_filename.

* Remove reserved characters (for Windows based systems)
    TRANSLATE lv_filename USING '/ \ : " * > < ? | '.

    lt_rawdata = cl_bcs_convert=>xstring_to_solix( iv_binstring ).

    CONCATENATE gv_full_folder lv_filename INTO lv_filename SEPARATED BY '\'.

    cl_gui_frontend_services=>gui_download(
      EXPORTING
        bin_filesize              = xstrlen( iv_binstring )
        filename                  = lv_filename
        filetype                  = 'BIN'
      CHANGING
        data_tab                  = lt_rawdata
      EXCEPTIONS
        file_write_error          = 1
        no_batch                  = 2
        gui_refuse_filetransfer   = 3
        invalid_type              = 4
        no_authority              = 5
        unknown_error             = 6
        header_not_allowed        = 7
        separator_not_allowed     = 8
        filesize_not_allowed      = 9
        header_too_long           = 10
        dp_error_create           = 11
        dp_error_send             = 12
        dp_error_write            = 13
        unknown_dp_error          = 14
        access_denied             = 15
        dp_out_of_memory          = 16
        disk_full                 = 17
        dp_timeout                = 18
        file_not_found            = 19
        dataprovider_exception    = 20
        control_flush_error       = 21
        not_supported_by_gui      = 22
        error_no_gui              = 23
        OTHERS                    = 24 ).
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( 'error from gui_download'(e01) ).
    ELSE.
      go_reporter->fill_report_table( EXPORTING is_trkorr = is_trkorr
                                                iv_filename = lv_filename ).
    ENDIF.


  ENDMETHOD.

  METHOD generate_files.

    DATA: ls_trkorr       LIKE LINE OF it_trkorr,
          lv_zipbinstring TYPE xstring.

    LOOP AT it_trkorr INTO ls_trkorr.

      lv_zipbinstring = zcl_abapgit_transport_mass=>zip( EXPORTING iv_trkorr = ls_trkorr-trkorr
                                                                   iv_logic  = iv_logic ).

      me->save_binstring( EXPORTING iv_binstring = lv_zipbinstring
                                    is_trkorr    = ls_trkorr ).

    ENDLOOP. "it_trkorr

  ENDMETHOD.

ENDCLASS.
*======================================================================*

*======================== SELECTION SCREEN ============================*
SELECTION-SCREEN BEGIN OF BLOCK a WITH FRAME TITLE TEXT-t01.

* Transport request
SELECT-OPTIONS s_trkorr FOR lcl_data_selector=>gv_trkorr OBLIGATORY.

* Output Folder
PARAMETERS p_folder TYPE lcl_transport_zipper=>ty_folder OBLIGATORY LOWER CASE.

* Package logic
PARAMETERS p_logic TYPE lcl_transport_zipper=>ty_logic OBLIGATORY DEFAULT lcl_transport_zipper=>gc_logic_full.

SELECTION-SCREEN END OF BLOCK a.
*======================================================================*

*============================= EVENTS =================================*
START-OF-SELECTION.
  PERFORM f_main.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_folder.
  lcl_matchcodes=>f4_folder( CHANGING cv_folder = p_folder ).

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_trkorr-low.
  lcl_matchcodes=>f4_transport_request( CHANGING cv_trkorr = s_trkorr-low ).

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_trkorr-high.
  lcl_matchcodes=>f4_transport_request( CHANGING cv_trkorr = s_trkorr-high ).

AT SELECTION-SCREEN.
  PERFORM f_check_folder USING p_folder.

*======================================================================*

*&---------------------------------------------------------------------*
*& Form F_MAIN
*&---------------------------------------------------------------------*
FORM f_main.

  DATA:
    lt_trkorr   TYPE lcl_data_selector=>tt_trkorr,
    ls_sel_crit TYPE lcl_data_selector=>ty_sel_criterias.

  DATA:
    lo_transport_zipper TYPE REF TO lcl_transport_zipper,
    lo_reporter         TYPE REF TO lcl_reporter,
    lo_except           TYPE REF TO cx_root.

  ls_sel_crit-t_r_trkorr[] = s_trkorr[].

  TRY.

      lt_trkorr = lcl_data_selector=>get_transport_requests( EXPORTING is_sel_crit = ls_sel_crit ).

      IF lt_trkorr[] IS NOT INITIAL.

* Instantiate reporter
        lo_reporter = NEW lcl_reporter( ).

* Instantiate transport zipper object that will also create the timestamped output folder
        lo_transport_zipper = NEW lcl_transport_zipper( iv_folder   = p_folder
                                                        io_reporter = lo_reporter ).

* Generate the local zip files from the given list of transport requests
        lo_transport_zipper->generate_files( EXPORTING it_trkorr = lt_trkorr
                                                       iv_logic  = p_logic ).

      ELSE.
* No data found for the provided selection criterias
        RAISE EXCEPTION TYPE cx_wrong_data MESSAGE e008(ciwb_ui).
      ENDIF.

      lo_reporter->display_report( ).

    CATCH cx_wrong_data
          zcx_abapgit_exception INTO lo_except.

      MESSAGE lo_except->get_text( ) TYPE 'E'.

  ENDTRY.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form F_CHECK_FOLDER
*&---------------------------------------------------------------------*
FORM f_check_folder  USING iv_folder TYPE string.

  DATA lo_except TYPE REF TO cx_root.

  TRY.
      IF lcl_transport_zipper=>does_folder_exist( EXPORTING iv_folder = iv_folder ) = abap_false.
        SET CURSOR FIELD 'P_FOLDER'.
        MESSAGE e137(c$) WITH 'Invalid folder'(m04) iv_folder.
      ENDIF.
    CATCH cx_wrong_data INTO lo_except.
      MESSAGE lo_except->get_text( ) TYPE 'E'.
  ENDTRY.


ENDFORM.