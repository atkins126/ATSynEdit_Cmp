{
Copyright (C) Alexey Torgashin, uvviewsoft.com
License: MPL 2.0 or LGPL
}
unit ATSynEdit_Form_Complete;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics,
  Dialogs,
  LclProc, LclType,
  ATSynEdit,
  ATSynEdit_Carets,
  ATSynEdit_Commands,
  ATStringProc,
  ATStringProc_Separator,
  ATListbox,
  ATFlatThemes,
  Math;

type
  TATCompletionPropEvent = procedure (Sender: TObject;
    out AText: string; out ACharsLeft, ACharsRight: integer) of object;
  TATCompletionResultEvent = procedure (Sender: TObject;
    const ASnippetId: string; ASnippetIndex: integer) of object;

//AText is #13-separated strings, each string is '|'-separated items.
//Usually item_0 is prefix to show,
//        item_1 is actual text (inserted on Enter),
//        item_2..etc are only to show.
//e.g. 'func|Func1|(param1, param2)'+#13+'var|Var1'+#13+'var|Var2'
//Item for text can have suffixes after #1: text+#1+suffix_before_caret+#1+suffix_after_caret

procedure DoEditorCompletionListbox(AEd: TATSynEdit;
  AOnGetProp: TATCompletionPropEvent;
  AOnResult: TATCompletionResultEvent = nil;
  const ASnippetId: string = '';
  ASelectedIndex: integer = 0;
  AAllowCarets: boolean = false);

procedure EditorGetCurrentWord(Ed: TATSynEdit;
  APosX, APosY: integer;
  const ANonWordChars: atString;
  out AWord: atString; out ACharsLeft, ACharsRight: integer);

type
  { TFormATSynEditComplete }

  TFormATSynEditComplete = class(TForm)
    List: TATListbox;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDeactivate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
    procedure FormUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
    procedure ListClick(Sender: TObject);
    procedure ListDrawItem(Sender: TObject; C: TCanvas; AIndex: integer;
      const ARect: TRect);
  private
    { private declarations }
    SList: TStringlist;
    FOnGetProp: TATCompletionPropEvent;
    FOnResult: TATCompletionResultEvent;
    FEdit: TATSynEdit;
    FCharsLeft,
    FCharsRight: integer;
    FHintWnd: THintWindow;
    FSnippetId: string;
    FSelectedIndex: integer;
    procedure DoHintHide;
    procedure DoHintShow(const AHint: string);
    procedure DoReplaceTo(const AStr: string; AWithBracket: boolean);
    procedure DoResult;
    procedure DoUpdate;
    function GetItemText(const AText: string; AIndex: integer): string;
    procedure GetResultText(out AText: string; out AWithBracket: boolean);
  public
    { public declarations }
    property Editor: TATSynEdit read FEdit write FEdit;
    property OnGetProp: TATCompletionPropEvent read FOnGetProp write FOnGetProp;
    property OnResult: TATCompletionResultEvent read FOnResult write FOnResult;
    property SnippetId: string read FSnippetId write FSnippetId;
    property SelectedIndex: integer read FSelectedIndex write FSelectedIndex;
  end;

const
  cCompletionColumnCount = 5;

type
  TATCompletionUpDownAtEdge = (
    cudIgnore,
    cudWrap,
    cudCloseForm
    );

  TATCompletionOptions = record
    ColorFontPrefix: TColor;
    ColorFontParams: TColor;
    CommitChars: string;
    CloseChars: string;
    IndexOfText: integer;
    IndexOfDesc: integer;
    ColumnsSep: char;
    HintSep: char;
    HintMultiLineSep: char;
    HintOnlyInTooltip: boolean;
    SuffixSep: char;
    AppendOpeningBracket: boolean;
    ListSort: boolean;
    UpDownAtEdge: TATCompletionUpDownAtEdge;
    BorderSize: integer;
    FormSizeX: integer;
    FormSizeY: integer;
    HintSizeX: integer;
    TextIndent0: integer;
    TextIndent: integer;
  end;

var
  CompletionOps: TATCompletionOptions;

implementation

{$R *.lfm}

var
  FormComplete: TFormATSynEditComplete = nil;

procedure DoEditorCompletionListbox(AEd: TATSynEdit;
  AOnGetProp: TATCompletionPropEvent;
  AOnResult: TATCompletionResultEvent = nil;
  const ASnippetId: string = '';
  ASelectedIndex: integer = 0;
  AAllowCarets: boolean = false);
begin
  if AEd.ModeReadOnly then exit;
  if AEd.Carets.Count>1 then
    if not AAllowCarets then exit;

  if FormComplete=nil then
    FormComplete:= TFormATSynEditComplete.Create(nil);

  FormComplete.List.ItemIndex:= 0;
  FormComplete.List.ItemTop:= 0;
  FormComplete.Editor:= AEd;
  FormComplete.SelectedIndex:= ASelectedIndex;
  FormComplete.SnippetId:= ASnippetId;
  FormComplete.OnGetProp:= AOnGetProp;
  FormComplete.OnResult:= AOnResult;
  FormComplete.DoUpdate;
end;

procedure TFormATSynEditComplete.DoReplaceTo(const AStr: string; AWithBracket: boolean);
var
  Caret: TATCaretItem;
  Pos, Shift, PosAfter: TPoint;
  StrText, Str1, Str2, StrToInsert: atString;
  Sep: TATStringSeparator;
  i: integer;
begin
  if AStr='' then exit;
  Sep.Init(AStr, CompletionOps.SuffixSep);
  Sep.GetItemStr(StrText);
  Sep.GetItemStr(Str1);
  Sep.GetItemStr(Str2);

  //must support carets, for HTML
  Editor.Strings.BeginUndoGroup;
  try
    for i:= 0 to Editor.Carets.Count-1 do
    begin
      Caret:= Editor.Carets[i];
      Pos.X:= Caret.PosX;
      Pos.Y:= Caret.PosY;

      FCharsLeft:= Min(Pos.X, FCharsLeft);
      Dec(Pos.X, FCharsLeft);

      Editor.Strings.TextDeleteRight(Pos.X, Pos.Y, FCharsLeft+FCharsRight, Shift, PosAfter, false);

      StrToInsert:= StrText+Str1+Str2;
      if AWithBracket then
        if Editor.Strings.TextSubstring(Pos.X, Pos.Y, Pos.X+1, Pos.Y)<>'(' then
          StrToInsert+= '(';

      Editor.Strings.TextInsert(Pos.X, Pos.Y, StrToInsert, false, Shift, PosAfter);

      //adjust markers/attrs
      Editor.DoCaretsShift(i, Pos.X, Pos.Y,
        Length(StrToInsert) - FCharsLeft-FCharsRight, 0,
        PosAfter
        );

      Caret.PosX:= Pos.X+Length(StrToInsert)-Length(Str2);
      Caret.EndX:= -1;
      Caret.EndY:= -1;
    end;
  finally
    Editor.Strings.EndUndoGroup;
    Editor.Update(true);
    Editor.DoEventChange;
  end;
end;

{ TFormATSynEditComplete }

procedure TFormATSynEditComplete.FormCreate(Sender: TObject);
begin
  SList:= TStringList.Create;
  FHintWnd:= THintWindow.Create(Self);
end;

procedure TFormATSynEditComplete.FormDeactivate(Sender: TObject);
begin
  Close;
end;

procedure TFormATSynEditComplete.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  DoHintHide;
  if Assigned(FEdit) then
    FEdit.OptCaretStopUnfocused:= true;
  CloseAction:= caHide;
end;

procedure TFormATSynEditComplete.FormDestroy(Sender: TObject);
begin
  SList.Free;
end;

procedure TFormATSynEditComplete.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (key=vk_up) and (shift=[]) then
  begin
    if List.ItemIndex>0 then
      List.ItemIndex:= List.ItemIndex-1
    else
    case CompletionOps.UpDownAtEdge of
      cudWrap:
        List.ItemIndex:= List.ItemCount-1;
      cudCloseForm:
        Close;
    end;
    key:= 0;
    exit
  end;

  if (key=vk_down) and (shift=[]) then
  begin
    if List.ItemIndex<List.ItemCount-1 then
      List.ItemIndex:= List.ItemIndex+1
    else
    case CompletionOps.UpDownAtEdge of
      cudWrap:
        List.ItemIndex:= 0;
      cudCloseForm:
        Close;
    end;
    key:= 0;
    exit
  end;

  if (key=VK_PRIOR) and (shift=[]) then
  begin
    List.ItemIndex:= Max(0, List.ItemIndex-List.VisibleItems);
    key:= 0;
    exit
  end;

  if (key=VK_NEXT) and (shift=[]) then
  begin
    List.ItemIndex:= Min(List.Itemcount-1, List.ItemIndex+List.VisibleItems);
    key:= 0;
    exit
  end;

  if (key=vk_home) then
  begin
    List.ItemIndex:= 0;
    key:= 0;
    exit
  end;

  if (key=vk_end) then
  begin
    List.ItemIndex:= List.ItemCount-1;
    key:= 0;
    exit
  end;

  if (key=VK_ESCAPE) then
  begin
    Close;
    key:= 0;
    exit
  end;

  if (key=VK_RETURN) or (key=VK_TAB) then
  begin
    DoResult;
    key:= 0;
    exit
  end;

  if (key=VK_LEFT) and (shift=[]) then
  begin
    Editor.DoCommand(cCommand_KeyLeft, '');
    DoUpdate;
    key:= 0;
    exit
  end;

  if (key=VK_RIGHT) and (shift=[]) then
  begin
    Editor.DoCommand(cCommand_KeyRight, '');
    DoUpdate;
    key:= 0;
    exit
  end;
end;

procedure TFormATSynEditComplete.FormShow(Sender: TObject);
begin
  if Assigned(FEdit) then
    FEdit.OptCaretStopUnfocused:= false;

  if (FSelectedIndex>=0) and (FSelectedIndex<List.ItemCount) then
    List.ItemIndex:= FSelectedIndex;
end;

procedure TFormATSynEditComplete.FormUTF8KeyPress(Sender: TObject;
  var UTF8Key: TUTF8Char);
var
  Str: atString;
  bCommit, bClose: boolean;
begin
  inherited;

  //backsp
  if (UTF8Key=#8) then
  begin
    FEdit.DoCommand(cCommand_KeyBackspace, '');
    DoUpdate;
    UTF8Key:= '';
    exit;
  end;

  //skip control Ascii chars
  if Ord(UTF8Key[1])<32 then Exit;

  bCommit:= Pos(UTF8Key, CompletionOps.CommitChars)>0;
  bClose:= Pos(UTF8Key, CompletionOps.CloseChars)>0;

  if bCommit then
    DoResult;

  Str:= UTF8Decode(UTF8Key);
  FEdit.DoCommand(cCommand_TextInsert, Str);
  DoUpdate;

  if bCommit or bClose then
    Close;

  UTF8Key:= '';
end;

procedure TFormATSynEditComplete.ListClick(Sender: TObject);
begin
  DoResult;
end;

function TFormATSynEditComplete.GetItemText(const AText: string; AIndex: integer): string;
var
  Sep: TATStringSeparator;
  i: integer;
begin
  Sep.Init(AText, CompletionOps.ColumnsSep);
  for i:= 0 to AIndex do
    Sep.GetItemStr(Result);
end;

procedure TFormATSynEditComplete.GetResultText(out AText: string; out AWithBracket: boolean);
var
  SDesc: string;
begin
  AText:= '';
  if List.ItemIndex>=0 then
  begin
    AText:= GetItemText(SList[List.ItemIndex], CompletionOps.IndexOfText);
    SDesc:= GetItemText(SList[List.ItemIndex], CompletionOps.IndexOfDesc);

    AWithBracket:=
      CompletionOps.AppendOpeningBracket and
      SBeginsWith(SDesc, '(');
  end;
end;

procedure TFormATSynEditComplete.ListDrawItem(Sender: TObject; C: TCanvas;
  AIndex: integer; const ARect: TRect);
var
  Sep: TATStringSeparator;
  SLongItem, SItem, SHint: string;
  NSize, i: integer;
begin
  SLongItem:= SList[AIndex];

  if AIndex=List.ItemIndex then
    C.Brush.Color:= ATFlatTheme.ColorBgListboxSel
  else
    C.Brush.Color:= ATFlatTheme.ColorBgListbox;
  C.FillRect(ARect);

  C.Font.Name:= ATFlatTheme.FontName;
  C.Font.Size:= ATFlatTheme.DoScaleFont(ATFlatTheme.FontSize);

  //alternate listbox: OnResult is set, then 3 columns, tab-separated:
  //paint column1 at left,
  //paint column2 at right
  if Assigned(FOnResult) then
  begin
    Sep.Init(SLongItem, #9);
    Sep.GetItemStr(SItem);
    Sep.GetItemStr(SHint);

    //prefix
    C.Font.Color:= CompletionOps.ColorFontPrefix;
    C.TextOut(ARect.Left+List.ClientWidth-List.Canvas.TextWidth(SHint)-CompletionOps.TextIndent0, ARect.Top, SHint);

    //text
    C.Font.Color:= ATFlatTheme.ColorFontListbox;
    C.TextOut(ARect.Left+CompletionOps.TextIndent0, ARect.Top, SItem);

    exit;
  end;

  //usual case, n columns, tab-char separates hint (in hint window)
  if Pos(CompletionOps.HintSep, SLongItem)>0 then
  begin
    SSplitByChar(SLongItem, CompletionOps.HintSep, SItem, SHint);
    if CompletionOps.HintOnlyInTooltip then
      SLongItem:= SItem;
    SHint:= StringReplace(SHint, CompletionOps.HintMultiLineSep, #10, [rfReplaceAll]);
    if AIndex=List.ItemIndex then
      DoHintShow(SHint);
  end;

  NSize:= CompletionOps.TextIndent0;

  Sep.Init(SLongItem, CompletionOps.ColumnsSep);
  for i:= 0 to cCompletionColumnCount-1 do
  begin
    Sep.GetItemStr(SItem);

    if i=CompletionOps.IndexOfText then
      SItem:= SGetItem(SItem, CompletionOps.SuffixSep);

    if i=CompletionOps.IndexOfText then
      C.Font.Color:= ATFlatTheme.ColorFontListbox
    else
    if i=CompletionOps.IndexOfDesc then
      C.Font.Color:= CompletionOps.ColorFontParams
    else
      C.Font.Color:= CompletionOps.ColorFontPrefix;

    C.TextOut(ARect.Left+NSize, ARect.Top, SItem);
    Inc(NSize, C.TextWidth(SItem)+CompletionOps.TextIndent);
  end;
end;

procedure TFormATSynEditComplete.DoResult;
var
  Str: string;
  WithBracket: boolean;
begin
  if Assigned(FOnResult) then
    FOnResult(Self, FSnippetId, List.ItemIndex)
  else
  begin
    GetResultText(Str, WithBracket);
    DoReplaceTo(Str, WithBracket);
  end;

  Close;
end;

procedure TFormATSynEditComplete.DoUpdate;
var
  AText: string;
  P: TPoint;
  RectMon: TRect;
  NewY: integer;
begin
  if Assigned(FOnGetProp) then
    FOnGetProp(Editor, AText, FCharsLeft, FCharsRight);

  if (AText='') then
    begin Close; exit end;

  SList.Text:= AText;
  if SList.Count=0 then exit;
  if CompletionOps.ListSort then SList.Sort;

  List.VirtualItemCount:= SList.Count;
  List.ItemIndex:= 0;

  Color:= ATFlatTheme.ColorBgListbox;
  List.BorderSpacing.Around:= CompletionOps.BorderSize;
  List.Invalidate;

  P.X:= Max(0, Editor.Carets[0].PosX-FCharsLeft);
  P.Y:= Editor.Carets[0].PosY;
  P:= Editor.CaretPosToClientPos(P);
  Inc(P.Y, Editor.TextCharSize.Y);
  P:= Editor.ClientToScreen(P);

  RectMon:= Screen.MonitorFromPoint(P).WorkareaRect;

  //check that form fits on the bottom
  if P.Y+CompletionOps.FormSizeY>= RectMon.Bottom then
  begin
    NewY:= P.Y-Editor.TextCharSize.y-CompletionOps.FormSizeY;
    if NewY>=RectMon.Top then
      P.Y:= NewY;
  end;

  //check that form fits on the right
  P.X:= Max(RectMon.Left, Min(P.X, RectMon.Right-CompletionOps.FormSizeX));

  if Application.MainForm.FormStyle in [fsStayOnTop, fsSystemStayOnTop] then
    FormStyle:= Application.MainForm.FormStyle;

  SetBounds(P.X, P.Y, CompletionOps.FormSizeX, CompletionOps.FormSizeY);
  Show;
end;


procedure EditorGetCurrentWord(Ed: TATSynEdit;
  APosX, APosY: integer;
  const ANonWordChars: atString;
  out AWord: atString; out ACharsLeft, ACharsRight: integer);
var
  str: atString;
  n: integer;
begin
  AWord:= '';
  ACharsLeft:= 0;
  ACharsRight:= 0;

  if not Ed.Strings.IsIndexValid(APosY) then exit;
  str:= Ed.Strings.Lines[APosY];

  n:= APosX;
  if (n>Length(str)) then exit;

  while (n>0) and (IsCharWord(str[n], ANonWordChars)) do
  begin
    AWord:= str[n]+AWord;
    Dec(n);
    Inc(ACharsLeft);
  end;

  n:= APosX;
  while (n<Length(str)) and (IsCharWord(str[n+1], ANonWordChars)) do
  begin
    Inc(n);
    Inc(ACharsRight);
  end;
end;

procedure TFormATSynEditComplete.DoHintShow(const AHint: string);
var
  P: TPoint;
  R: TRect;
begin
  R:= FHintWnd.CalcHintRect(CompletionOps.HintSizeX, AHint, nil);

  P:= ClientToScreen(Point(Width, 0));
  OffsetRect(R, P.X, P.Y);

  FHintWnd.ActivateHint(R, AHint);
  FHintWnd.Invalidate; //for Win
  Editor.Invalidate; //for Win
end;

procedure TFormATSynEditComplete.DoHintHide;
begin
  if Assigned(FHintWnd) then
    FHintWnd.Hide;
end;


initialization

  FillChar(CompletionOps, SizeOf(CompletionOps), 0);
  with CompletionOps do
  begin
    ColorFontPrefix:= clPurple;
    ColorFontParams:= clGray;
    CommitChars:= ' .,;/\''"';
    CloseChars:= '<>()[]{}=';
    IndexOfText:= 1;
    IndexOfDesc:= 2;
    ColumnsSep:= '|';
    HintSep:= #9;
    HintMultiLineSep:= #2;
    HintOnlyInTooltip:= true;
    SuffixSep:= #1;
    AppendOpeningBracket:= true;
    ListSort:= false;
    UpDownAtEdge:= cudWrap;
    BorderSize:= 4;
    FormSizeX:= 500;
    FormSizeY:= 200;
    HintSizeX:= 400;
    TextIndent0:= 4;
    TextIndent:= 8;
  end;

finalization

  if Assigned(FormComplete) then
    FormComplete.Free;

end.

