#requires -version 2
# Fixed Windows PowerShell 2 / .NET 2.0 JSON implementation with no System.Web.Extensions.
# Standalone C# 2.0 parser; text-only OData and result serialization.
# Safe for LocalService; does not access filesystem/network/configuration.
$legacyJsonCSharp=@'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

public sealed class MspLegacyJson {
  public int MaxJsonLength = 262144;

  public object DeserializeObject(string input) {
    if (input==null || input.Length>MaxJsonLength) throw new FormatException("JSON size");
    Reader r=new Reader(input);
    object result=r.Value(0);
    r.White();
    if(r.Position!=input.Length) throw new FormatException("JSON trailing");
    return result;
  }
  public string Serialize(object value) {
    StringBuilder buffer=new StringBuilder();
    WriteValue(value,buffer,0);
    if(buffer.Length>MaxJsonLength)throw new FormatException("JSON output size");
    return buffer.ToString();
  }
  private static void WriteValue(object value, StringBuilder sb, int depth) {
    if(depth>32)throw new FormatException("JSON depth");
    if(value==null){sb.Append("null");return;}
    string text=value as string;
    if(text!=null){WriteString(text,sb);return;}
    if(value is bool){sb.Append((bool)value?"true":"false");return;}
    IDictionary map=value as IDictionary;
    if(map!=null) {
      sb.Append('{');bool first=true;
      foreach(DictionaryEntry item in map){
        string key=item.Key as string;
        if(key==null)throw new FormatException("JSON key type");
        if(!first)sb.Append(',');
        WriteString(key,sb);sb.Append(':');WriteValue(item.Value,sb,depth+1);
        first=false;
      }
      sb.Append('}');return;
    }
    IEnumerable seq=value as IEnumerable;
    if(seq!=null) {
      sb.Append('[');bool first=true;
      foreach(object item in seq){
        if(!first)sb.Append(',');
        WriteValue(item,sb,depth+1);first=false;
      }
      sb.Append(']');return;
    }
    if(value is byte || value is sbyte || value is short || value is ushort ||
       value is int || value is uint || value is long || value is ulong ||
       value is float || value is double || value is decimal) {
      string n=Convert.ToString(value,CultureInfo.InvariantCulture);
      if(n=="NaN"||n=="Infinity"||n=="-Infinity") throw new FormatException("JSON numeric");
      sb.Append(n);return;
    }
    throw new FormatException("JSON value type");
  }
  private static void WriteString(string input,StringBuilder sb) {
    sb.Append('"');
    foreach(char ch in input){
      if(ch=='"'){sb.Append("\\\"");continue;}
      if(ch=='\\'){sb.Append("\\\\");continue;}
      if(ch=='\b'){sb.Append("\\b");continue;}
      if(ch=='\f'){sb.Append("\\f");continue;}
      if(ch=='\n'){sb.Append("\\n");continue;}
      if(ch=='\r'){sb.Append("\\r");continue;}
      if(ch=='\t'){sb.Append("\\t");continue;}
      if(ch<32 || Char.IsSurrogate(ch)) {
        sb.Append("\\u");sb.Append(((int)ch).ToString("x4",CultureInfo.InvariantCulture));
        continue;
      }
      sb.Append(ch);
    }
    sb.Append('"');
  }

  private sealed class Reader {
    private readonly string t;
    private int p;
    public int Position {get{return p;}}
    public Reader(string text){t=text;p=0;}
    public void White(){while(p<t.Length&&(t[p]==' '||t[p]=='\n'||t[p]=='\r'||t[p]=='\t'))p++;}
    private bool Eat(char c){White();if(p<t.Length&&t[p]==c){p++;return true;}return false;}
    private void Need(char c){if(!Eat(c))throw new FormatException("JSON expected delimiter");}
    public object Value(int depth){
      if(depth>32)throw new FormatException("JSON too deep");
      White();if(p>=t.Length)throw new FormatException("JSON truncated");
      char c=t[p];
      if(c=='"')return Str();
      if(c=='{')return Obj(depth+1);
      if(c=='[')return Arr(depth+1);
      if(c=='t'&&Word("true"))return true;
      if(c=='f'&&Word("false"))return false;
      if(c=='n'&&Word("null"))return null;
      if(c=='-'||(c>='0'&&c<='9'))return Number();
      throw new FormatException("JSON invalid token");
    }
    private bool Word(string word){
      if(p+word.Length>t.Length||String.CompareOrdinal(t,p,word,0,word.Length)!=0)return false;
      p+=word.Length;return true;
    }
    private Dictionary<string,object> Obj(int depth){
      Need('{');
      Dictionary<string,object> result=new Dictionary<string,object>(StringComparer.Ordinal);
      if(Eat('}'))return result;
      while(true){
        White();if(p>=t.Length||t[p]!='"')throw new FormatException("JSON object key");
        string key=Str();
        Need(':');
        if(result.ContainsKey(key))throw new FormatException("JSON duplicate key");
        result.Add(key,Value(depth));
        if(Eat('}'))return result;
        Need(',');
      }
    }
    private object[] Arr(int depth){
      Need('[');
      List<object> result=new List<object>();
      if(Eat(']'))return result.ToArray();
      while(true){
        result.Add(Value(depth));
        if(result.Count>10000)throw new FormatException("JSON array limit");
        if(Eat(']'))return result.ToArray();
        Need(',');
      }
    }
    private string Str(){
      if(p>=t.Length||t[p]!='"')throw new FormatException("JSON string");
      p++;
      StringBuilder outText=new StringBuilder();
      bool done=false;
      while(p<t.Length){
        char c=t[p++];
        if(c=='"'){done=true;break;}
        if(c<32)throw new FormatException("JSON control");
        if(c!='\\'){outText.Append(c);continue;}
        if(p>=t.Length)throw new FormatException("JSON escape truncated");
        char esc=t[p++];
        if(esc=='"'||esc=='\\'||esc=='/'){outText.Append(esc);continue;}
        if(esc=='b'){outText.Append('\b');continue;}
        if(esc=='f'){outText.Append('\f');continue;}
        if(esc=='n'){outText.Append('\n');continue;}
        if(esc=='r'){outText.Append('\r');continue;}
        if(esc=='t'){outText.Append('\t');continue;}
        if(esc=='u'){
          if(p+4>t.Length)throw new FormatException("JSON unicode truncated");
          int code=0;
          for(int i=0;i<4;i++){
            char h=t[p++];
            int x=(h>='0'&&h<='9')?h-'0':
                (h>='a'&&h<='f')?h-'a'+10:
                (h>='A'&&h<='F')?h-'A'+10:-1;
            if(x<0)throw new FormatException("JSON unicode invalid");
            code=(code<<4)+x;
          }
          outText.Append((char)code);continue;
        }
        throw new FormatException("JSON unknown escape");
      }
      if(!done)throw new FormatException("JSON string truncated");
      return outText.ToString();
    }
    private decimal Number(){
      int start=p;
      if(t[p]=='-')p++;
      if(p>=t.Length)throw new FormatException("JSON number");
      if(t[p]=='0')p++;
      else {
        if(t[p]<'1'||t[p]>'9')throw new FormatException("JSON number");
        while(p<t.Length&&t[p]>='0'&&t[p]<='9')p++;
      }
      if(p<t.Length&&t[p]=='.'){
        p++;int digits=p;
        while(p<t.Length&&t[p]>='0'&&t[p]<='9')p++;
        if(p==digits)throw new FormatException("JSON fraction");
      }
      if(p<t.Length&&(t[p]=='e'||t[p]=='E')){
        p++;if(p<t.Length&&(t[p]=='+'||t[p]=='-'))p++;
        int digits=p;
        while(p<t.Length&&t[p]>='0'&&t[p]<='9')p++;
        if(p==digits)throw new FormatException("JSON exponent");
      }
      string num=t.Substring(start,p-start);
      return Decimal.Parse(num,NumberStyles.Float,CultureInfo.InvariantCulture);
    }
  }
}
'@
if (-not ('MspLegacyJson' -as [type])) {
  Add-Type -TypeDefinition $legacyJsonCSharp -Language CSharp -ErrorAction Stop
}
