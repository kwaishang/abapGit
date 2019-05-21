CLASS zcl_abapgit_transport_mass DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    TYPES:
      tt_trkorr TYPE RANGE OF e070-trkorr .

    CONSTANTS gc_fm_name TYPE rs38l-name VALUE 'Z_ABAPGIT_TRANSPORTS_2_ZIP' ##NO_TEXT.

    CLASS-METHODS is_available
      RETURNING
        VALUE(rv_available) TYPE abap_bool .
    CLASS-METHODS run.
    CLASS-METHODS zip
      IMPORTING
        !is_trkorr     TYPE trwbo_request_header
        !iv_logic      TYPE string OPTIONAL
      RETURNING
        VALUE(rv_xstr) TYPE xstring
      RAISING
        zcx_abapgit_exception .
    CLASS-METHODS to_tadir
      IMPORTING
        !it_transport_headers TYPE trwbo_request_headers
      RETURNING
        VALUE(rt_tadir)       TYPE zif_abapgit_definitions=>ty_tadir_tt
      RAISING
        zcx_abapgit_exception .
  PROTECTED SECTION.
  PRIVATE SECTION.

    CLASS-METHODS read_requests
      IMPORTING
        !it_trkorr         TYPE trwbo_request_headers
      RETURNING
        VALUE(rt_requests) TYPE trwbo_requests
      RAISING
        zcx_abapgit_exception .
    CLASS-METHODS find_top_package
      IMPORTING
        !it_tadir         TYPE zif_abapgit_definitions=>ty_tadir_tt
      RETURNING
        VALUE(rv_package) TYPE devclass .
    CLASS-METHODS resolve
      IMPORTING
        !it_requests    TYPE trwbo_requests
      RETURNING
        VALUE(rt_tadir) TYPE zif_abapgit_definitions=>ty_tadir_tt
      RAISING
        zcx_abapgit_exception .
ENDCLASS.



CLASS ZCL_ABAPGIT_TRANSPORT_MASS IMPLEMENTATION.


  METHOD find_top_package.
* assumption: all objects in transport share a common super package

    DATA: lt_obj   TYPE zif_abapgit_sap_package=>ty_devclass_tt,
          lt_super TYPE zif_abapgit_sap_package=>ty_devclass_tt,
          lv_super LIKE LINE OF lt_super,
          lv_index TYPE i.

    FIELD-SYMBOLS: <ls_tadir> LIKE LINE OF it_tadir.


    READ TABLE it_tadir INDEX 1 ASSIGNING <ls_tadir>.
    ASSERT sy-subrc = 0.
    lt_super = zcl_abapgit_factory=>get_sap_package( <ls_tadir>-devclass )->list_superpackages( ).

    LOOP AT it_tadir ASSIGNING <ls_tadir>.
      lt_obj = zcl_abapgit_factory=>get_sap_package( <ls_tadir>-devclass )->list_superpackages( ).

* filter out possibilities from lt_super
      LOOP AT lt_super INTO lv_super.
        lv_index = sy-tabix.
        READ TABLE lt_obj FROM lv_super TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          DELETE lt_super INDEX lv_index.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    READ TABLE lt_super INDEX lines( lt_super ) INTO rv_package.
  ENDMETHOD.


  METHOD is_available.

* Mass Transport to ZIP file function module
* Use this check for the abap_merger version ( installator )
    CALL FUNCTION 'FUNCTION_EXISTS'
      EXPORTING
        funcname           = gc_fm_name
      EXCEPTIONS
        function_not_exist = 1
        OTHERS             = 2.
    IF sy-subrc = 0.
      rv_available = abap_true.
    ELSE.
      rv_available = abap_false.
    ENDIF.

  ENDMETHOD.


  METHOD read_requests.
    DATA lt_requests LIKE rt_requests.
    FIELD-SYMBOLS <ls_trkorr> LIKE LINE OF it_trkorr.

    LOOP AT it_trkorr ASSIGNING <ls_trkorr>.
      CALL FUNCTION 'TR_READ_REQUEST_WITH_TASKS'
        EXPORTING
          iv_trkorr     = <ls_trkorr>-trkorr
        IMPORTING
          et_requests   = lt_requests
        EXCEPTIONS
          invalid_input = 1
          OTHERS        = 2.
      IF sy-subrc <> 0.
        zcx_abapgit_exception=>raise( 'error from TR_READ_REQUEST_WITH_TASKS' ).
      ENDIF.

      APPEND LINES OF lt_requests TO rt_requests.
    ENDLOOP.
  ENDMETHOD.


  METHOD resolve.
    DATA: lv_object     TYPE tadir-object,
          lv_obj_name   TYPE tadir-obj_name,
          lv_trobj_name TYPE trobj_name,
          ls_tadir      TYPE zif_abapgit_definitions=>ty_tadir.

    FIELD-SYMBOLS: <ls_request> LIKE LINE OF it_requests,
                   <ls_object>  LIKE LINE OF <ls_request>-objects.


    LOOP AT it_requests ASSIGNING <ls_request>.
      LOOP AT <ls_request>-objects ASSIGNING <ls_object>.
        IF <ls_object>-pgmid = 'LIMU'.
          CALL FUNCTION 'GET_R3TR_OBJECT_FROM_LIMU_OBJ'
            EXPORTING
              p_limu_objtype = <ls_object>-object
              p_limu_objname = <ls_object>-obj_name
            IMPORTING
              p_r3tr_objtype = lv_object
              p_r3tr_objname = lv_trobj_name
            EXCEPTIONS
              no_mapping     = 1
              OTHERS         = 2.
          IF sy-subrc <> 0.
            zcx_abapgit_exception=>raise( 'error from GET_R3TR_OBJECT_FROM_LIMU_OBJ' ).
          ENDIF.
          lv_obj_name = lv_trobj_name.
        ELSE.
          lv_object   = <ls_object>-object.
          lv_obj_name = <ls_object>-obj_name.
        ENDIF.

        ls_tadir = zcl_abapgit_factory=>get_tadir( )->read_single(
          iv_object   = lv_object
          iv_obj_name = lv_obj_name ).

        APPEND ls_tadir TO rt_tadir.
      ENDLOOP.
    ENDLOOP.

    SORT rt_tadir BY object ASCENDING obj_name ASCENDING.
    DELETE ADJACENT DUPLICATES FROM rt_tadir COMPARING object obj_name.
    DELETE rt_tadir WHERE table_line IS INITIAL.
  ENDMETHOD.


  METHOD run.

    CALL FUNCTION gc_fm_name.

  ENDMETHOD.


  METHOD to_tadir.
    DATA: lt_requests TYPE trwbo_requests.


    IF lines( it_transport_headers ) = 0.
      RETURN.
    ENDIF.

    lt_requests = read_requests( it_transport_headers ).
    rt_tadir = resolve( lt_requests ).
  ENDMETHOD.


  METHOD zip.

    DATA: lt_requests TYPE trwbo_requests,
          lt_tadir    TYPE zif_abapgit_definitions=>ty_tadir_tt,
          lv_package  TYPE devclass,
          ls_data     TYPE zif_abapgit_persistence=>ty_repo,
          lo_repo     TYPE REF TO zcl_abapgit_repo_offline,
          lt_trkorr   TYPE trwbo_request_headers.


    APPEND is_trkorr TO lt_trkorr.

    lt_requests = read_requests( lt_trkorr ).
    lt_tadir = resolve( lt_requests ).
    IF lines( lt_tadir ) = 0.
      zcx_abapgit_exception=>raise( 'empty transport' ).
    ENDIF.

    lv_package = find_top_package( lt_tadir ).
    IF lv_package IS INITIAL.
      zcx_abapgit_exception=>raise( 'error finding super package' ).
    ENDIF.

    ls_data-key         = 'TZIP'.
    ls_data-package     = lv_package.
    ls_data-dot_abapgit = zcl_abapgit_dot_abapgit=>build_default( )->get_data( ).

    IF iv_logic IS SUPPLIED.
      ls_data-dot_abapgit-folder_logic = iv_logic.
    ELSE.
      ls_data-dot_abapgit-folder_logic = zcl_abapgit_ui_factory=>get_popups( )->popup_folder_logic( ).
    ENDIF.

    CREATE OBJECT lo_repo
      EXPORTING
        is_data = ls_data.

    rv_xstr = zcl_abapgit_zip=>export(
      io_repo    = lo_repo
      it_filter  = lt_tadir
      iv_logflag = abap_false ).

  ENDMETHOD.
ENDCLASS.
