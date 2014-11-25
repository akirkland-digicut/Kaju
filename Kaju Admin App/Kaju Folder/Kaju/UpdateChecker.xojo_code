#tag Class
Protected Class UpdateChecker
	#tag Method, Flags = &h0
		Sub Constructor(preferencesFolder As FolderItem)
		  self.PrefFile = preferencesFolder.Child( kPreferencesName )
		  
		  LoadPrefs()
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Destructor()
		  SavePrefs()
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function DryRun() As Boolean
		  return mDryRun
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Execute()
		  // Pull the data from the URL, check it, and preset the window if needed
		  // Returns true if the app should quit in preparation of the update.
		  //
		  // The caller should be prepared to handle an exception in case of error.
		  
		  //
		  // Pull the raw data
		  //
		  
		  mDryRun = false
		  
		  if UpdateURL.Trim = "" then
		    raise new KajuException( KajuException.kErrorMissingUpdateURL )
		  end if
		  
		  dim http as new HTTPSecureSocket
		  http.Secure = self.Secure
		  dim raw as string = http.Get( self.UpdateURL, 5 )
		  if raw = "" then
		    raise new KajuException( KajuException.kErrorNoUpdateDataAvailable )
		  end if
		  
		  raw = raw.DefineEncoding( Encodings.UTF8 )
		  raw = ReplaceLineEndings( raw, EndOfLine.UNIX )
		  
		  dim firstLine as string = raw.NthField( EndOfLine.UNIX, 1 )
		  raw = raw.Mid( firstLine.Len + 2 )
		  
		  dim sig as string = firstLine.Left( kUpdatePacketMarker.Len )
		  if StrComp( sig, kUpdatePacketMarker, 0 ) <> 0 then
		    raise new KajuException( KajuException.kErrorIncorrectPacketMarker )
		  end if
		  
		  sig = firstLine.Mid( sig.Len + 1 )
		  sig = DecodeHex( sig )
		  if not Crypto.RSAVerifySignature( raw, sig, ServerPublicRSAKey ) then
		    raise new KajuException( KajuException.kErrorIncorrectPacketSignature )
		  end if
		  
		  ProcessUpdateData( raw )
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub IgnoreVersion(version As String)
		  if version <> "" and IgnoreVersionsPref.IndexOf( version ) = -1 then
		    IgnoreVersionsPref.Append version
		  end if
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function JSONToStringArray(data As JSONItem) As String()
		  dim ub as integer = data.Count - 1
		  dim arr() as string
		  redim arr( ub )
		  
		  for i as integer = 0 to ub
		    arr( i ) = data( i )
		  next
		  
		  return arr
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub LoadPrefs()
		  // Load the preferences from the known file
		  //
		  // Preferences are a JSON file
		  
		  if not PrefFile.Exists then
		    //
		    // Nothing to load
		    //
		    return
		  end if
		  
		  dim tis as TextInputStream = TextInputStream.Open( PrefFile )
		  dim raw as string = tis.ReadAll( Encodings.UTF8 )
		  
		  dim j as new JSONItem( raw )
		  
		  //
		  // Load the individual variables here
		  //
		  
		  dim ti as Introspection.TypeInfo = Introspection.GetType( self )
		  dim props() as Introspection.PropertyInfo = ti.GetProperties
		  for each prop as Introspection.PropertyInfo in props
		    dim thisName as string = prop.Name
		    if StrComp( thisName.Right( 4 ), "Pref", 0 ) <> 0 or not j.HasName( prop.Name ) then
		      continue for prop
		    end if
		    
		    if prop.PropertyType.Name = "String()" then
		      prop.Value( self ) = JSONToStringArray( j.Value( thisName ) )
		    else
		      prop.Value( self ) = j.Value( thisName )
		    end if
		  next
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub ProcessUpdateData(raw As String)
		  dim j as new JSONItem( raw )
		  dim versionDouble as double = if( DryRun, -1.0, Kaju.VersionToDouble( Kaju.AppVersionString ) )
		  
		  //
		  // Get an array of the info
		  //
		  dim ub as integer = j.Count - 1
		  dim info() as Kaju.UpdateInformation
		  for i as integer = 0 to ub
		    dim thisInfo as new Kaju.UpdateInformation( j( i ) )
		    
		    //
		    // See if the binary information is present
		    //
		    if thisInfo.PlatformBinary is nil then
		      continue for i
		    end if
		    
		    //
		    // See if the stage on this update is allowed
		    //
		    if thisInfo.StageCode < StageAllowed then
		      continue for i
		    end if
		    
		    //
		    // See if this update is for a higher version
		    //
		    if thisInfo.VersionAsDouble <= versionDouble then
		      continue for i
		    end if
		    
		    //
		    // An ignored version?
		    //
		    if HonorIgnored and IgnoreVersionsPref.IndexOf( thisInfo.Version ) <> -1 then
		      continue for i
		    end if
		    
		    //
		    // This is a viable update
		    //
		    info.Append thisInfo
		  next
		  
		  if info.Ubound <> -1 then
		    //
		    // There are updates
		    //
		    
		    Kaju.mUpdateInProgress = true
		    dim w as new KajuUpdateWindow
		    w.ChooseUpdate( self, info )
		  end if
		  
		  
		  
		  Exception err as RuntimeException
		    raise new KajuException( KajuException.kErrorBadUpdateData )
		    
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SavePrefs()
		  dim j as new JSONItem
		  
		  //
		  // Save the individual prefs here.
		  // Properties that end with "Pref" will be saved
		  //
		  
		  dim ti as Introspection.TypeInfo = Introspection.GetType( self )
		  dim props() as Introspection.PropertyInfo = ti.GetProperties
		  for each prop as Introspection.PropertyInfo in props
		    if StrComp( prop.Name.Right( 4 ), "Pref", 0 ) = 0 then
		      if prop.PropertyType.Name = "String()" then
		        j.Value( prop.Name ) = StringArrayToJSON( prop.Value( self ) )
		      else
		        j.Value( prop.Name ) = prop.Value( self )
		      end if
		    end if
		  next
		  
		  //
		  // Save the file
		  //
		  
		  j.Compact = false
		  dim raw as string = j.ToString
		  
		  dim tos as TextOutputStream = TextOutputStream.Create( PrefFile )
		  tos.Write raw
		  tos = nil
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function StringArrayToJSON(arr() As String) As JSONItem
		  dim j as new JSONItem( "[]" )
		  for i as integer = 0 to arr.Ubound
		    j.Append arr( i )
		  next
		  
		  return j
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub TestUpdate(jsonString As String)
		  // Allows a dry run with the update information that would otherwise be obtained
		  // from the UpdateURL
		  
		  mDryRun = true
		  ProcessUpdateData( jsonString )
		  
		End Sub
	#tag EndMethod


	#tag Hook, Flags = &h0
		Event ReadyToInstall()
	#tag EndHook

	#tag Hook, Flags = &h0
		Event RequiredUpdateDeclined()
	#tag EndHook


	#tag Property, Flags = &h0
		DefaultImage As Picture
	#tag EndProperty

	#tag Property, Flags = &h0
		DefaultUseTransparency As Boolean = True
	#tag EndProperty

	#tag Property, Flags = &h0
		HonorIgnored As Boolean = True
	#tag EndProperty

	#tag Property, Flags = &h21
		Private IgnoreVersionsPref() As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDryRun As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private PrefFile As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h0
		Secure As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		ServerPublicRSAKey As String
	#tag EndProperty

	#tag Property, Flags = &h0
		StageAllowed As Integer = App.Development
	#tag EndProperty

	#tag Property, Flags = &h0
		UpdateURL As String
	#tag EndProperty


	#tag Constant, Name = kPreferencesName, Type = String, Dynamic = False, Default = \"Kaju_Preferences", Scope = Private
	#tag EndConstant


End Class
#tag EndClass