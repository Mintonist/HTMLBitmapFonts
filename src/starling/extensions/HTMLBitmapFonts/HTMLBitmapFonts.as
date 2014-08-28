package starling.extensions.HTMLBitmapFonts
{
	import starling.display.Image;
	import starling.display.QuadBatch;
	import starling.text.BitmapChar;
	import starling.textures.Texture;
	import starling.utils.HAlign;
	import starling.utils.VAlign;
	
	/** 
	 * This class is used by HTMLTextField
	 * <br/><br/>
	 * XML's used by <code>add</code> and <code>addMultipleSizes</code>
	 * can be generated by <a href="http://kvazars.com/littera/">Littera</a> ou 
	 * <a href="http://www.angelcode.com/products/bmfont/">AngelCode - Bitmap Font Generator</a>
	 * <br/><br/>
	 * See an XML sample:
	 *
	 * <listing>
	 &lt;font&gt;
		 &lt;info face="BranchingMouse" size="40" /&gt;
		 &lt;common lineHeight="40" /&gt;
		 &lt;pages&gt; &lt;!-- currently, only one page is supported --&gt;
			 &lt;page id="0" file="texture.png" /&gt;
		 &lt;/pages&gt;
		 &lt;chars&gt;
			 &lt;char id="32" x="60" y="29" width="1" height="1" xoffset="0" yoffset="27" xadvance="8" /&gt;
		 	&lt;char id="33" x="155" y="144" width="9" height="21" xoffset="0" yoffset="6" xadvance="9" /&gt;
		 &lt;/chars&gt;
		 &lt;kernings&gt; &lt;!-- Kerning is optional --&gt;
		 	&lt;kerning first="83" second="83" amount="-4"/&gt;
		 &lt;/kernings&gt;
	 &lt;/font&gt;
	 * </listing>
	 * 
	 * Personnaly i use AssetManager for loading fonts and i just modified it like this: <br/>
	 * in loadQueue -> processXML :</br>
	 * <listing>
	 * 
	 else if( rootNode == "font" )
	 {
		 name 	= xml.info.&#64;face.toString();
		 fileName 	= getName(xml.pages.page.&#64;file.toString());
		 isBold 	= xml.info.&#64;bold == 1;
		 isItalic 	= xml.info.&#64;italic == 1;
		 
		 log("Adding html bitmap font '" + name + "'" + " _bold: " + isBold + " _italic: " + isItalic );
		 
		 fontTexture = getTexture( fileName );
		 HTMLTextField.registerBitmapFont( fontTexture, xml, xml.info.&#64;size, isBold, isItalic, name.toLowerCase() );
		 removeTexture( fileName, false );
		 
		 mLoadedHTMLFonts.push( name.toLowerCase() );
	 }
	 * </listing>
	 */ 
	public class HTMLBitmapFonts
	{
		// -- you can register emotes here --//
		
		private static var _emotesTxt				:Vector.<String>;
		private static var _emotesTextures			:Vector.<BitmapChar>;
		/** Register emote shortcut and the texture associated **/
		public static function registerEmote( txt:String, texture:Texture ):void
		{
			if( !_emotesTxt )
			{
				_emotesTxt 		= new Vector.<String>();
				_emotesTextures = new Vector.<BitmapChar>();
			}
			
			var id:int = _emotesTxt.indexOf(txt);
			if( id == -1 )
			{
				_emotesTxt.push( txt );
				_emotesTextures.push( new BitmapChar(int.MAX_VALUE, texture, 5, 0, texture.width+10) );
			}
			else
			{
				_emotesTxt[id] = txt;
				_emotesTextures[id] = new BitmapChar(int.MAX_VALUE, texture, 5, 0, texture.width+10);
			}
		}
		
		/** space char **/
		private static const CHAR_SPACE				:int = 32;
		/** tab char **/
		private static const CHAR_TAB				:int =  9;
		/** new line char **/
		private static const CHAR_NEWLINE			:int = 10;
		/** cariage return char **/
		private static const CHAR_CARRIAGE_RETURN	:int = 13;
		
		/** the base style for the font: the first added style **/
		private var _baseStyle						:int = -1;
		/** the base size for the font: the fisrt size added **/
		private var _baseSize						:int = -1;
		/** the globalScale fio the font, to get the near same result even if we apply scaling on Starling viewport. (usefull for android devices) **/
		private static var _globalScale				:Number = 1;
		/** the actual scale depending if we found a font for this globalScale **/
		private var _currentScale					:Number = 1;
		
		/** the font styles **/
		private var mFontStyles						:Vector.<BitmapFontStyle>;
		/** font name **/
		private var mName							:String;
		/** an helper image to construct the textField **/
		private var mHelperImage					:Image;
		
		/** the vector used for the lines **/
		private static var lines					:Vector.< Vector.<CharLocation> >;
		/** the vector for the line sizes **/
		private static var linesSizes				:Vector.<int>;
		
		/** CharLocation pool **/
		private static var mCharLocationPool		:Vector.<CharLocation>;
		public static function getCharLoc(char:BitmapChar):CharLocation
		{
			var c:CharLocation;
			if( mCharLocationPool.length > 0 )		
			{
				c = mCharLocationPool.pop();
				c.char = char;
			}
			else	c = new CharLocation(char);
			
			return c;
		}
		public static function returnCharLoc( value:CharLocation ):void
		{
			if( !value )	return;
			value.reset();
			mCharLocationPool.push( value );
		}
		
		/** Vector.<CharLocation> pool **/
		private static var mCharLocationVPool		:Vector.< Vector.<CharLocation> >;
		public static function getVCharLoc():Vector.<CharLocation>
		{
			if( mCharLocationVPool.length > 0 )		return mCharLocationVPool.pop();
			return new <CharLocation>[];
		}
		public static function returnVCharLoc( value:Vector.<CharLocation> ):void
		{
			value.fixed = false;
			value.length = 0;
			if( mCharLocationVPool.length < 50 ) 	mCharLocationVPool.push( value );
			else									value = null;
		}
		
		/** 
		 * Create a HTMLBitmapFont for a font familly
		 * @param name the name to register for this font.
		 **/
		public function HTMLBitmapFonts( name:String )
		{
			// créer la pool en statique si elle n'existe pas encore
			if( !mCharLocationPool )	mCharLocationPool 	= new <CharLocation>[];
			if( !mCharLocationVPool )	mCharLocationVPool 	= new <Vector.<CharLocation>>[];
			if( !lines )				lines 				= new <Vector.<CharLocation>>[];
			if( !linesSizes )			linesSizes			= new <int>[];
			
			// définir le nom de la font
			mName 				= name;
			// créer le tableau contenant les style de fonts
			mFontStyles 		= new Vector.<BitmapFontStyle>( BitmapFontStyle.NUM_STYLES, true );
		}
		
		/** Définir un scale global qui sera appliqué à tous les textes et qui sera utilisé pour trouver une taille de texte équivalente sans scaler le texte **/
		public static function set globalScale( value:Number ):void
		{
			_globalScale = value;
		}
		
		/** define the base size for the font **/
		public function set baseSize( value:Number ):void
		{
			_baseSize = value;
		}
		
		/** 
		 * define the base style for the font, this style must be valid and exists
		 * @see starling.extensions.HTMLBitmapFonts.BitmapFontStyle
		 * @see starling.extensions.HTMLBitmapFonts.BitmapFontStyle#REGULAR
		 * @see starling.extensions.HTMLBitmapFonts.BitmapFontStyle#BOLD
		 * @see starling.extensions.HTMLBitmapFonts.BitmapFontStyle#ITALIC
		 * @see starling.extensions.HTMLBitmapFonts.BitmapFontStyle#BOLD_ITALIC
		 **/
		public function set baseStyle( value:int ):void
		{
			if( value < BitmapFontStyle.NUM_STYLES && mFontStyles[value] != null )	_baseStyle = value;
		}
		
		/** 
		 * add multiple font sizes for this font
		 * @param textures the texture vector, one texture by font size
		 * @param fontsXML the xml vector, one xml by font size
		 * @param sizes the sizes vector, one size by font size, if null 
		 * @param bold point out if is a bold font
		 * @param italic point out if it is italic texture
		 **/
		public function addMultipleSizes( textures:Vector.<Texture>, fontsXml:Vector.<XML>, sizes:Vector.<Number>, bold:Boolean = false, italic:Boolean = false ):void
		{
			// récuperer l'index du style actuel
			var index:int = BitmapFontStyle.REGULAR;
			if( bold && italic ) 	index = BitmapFontStyle.BOLD_ITALIC;	
			else if( bold )			index = BitmapFontStyle.BOLD;
			else if( italic )		index = BitmapFontStyle.ITALIC;
			
			// créer le BitmapFontStyle pour le style si il n'existe pas encore
			if( !mFontStyles[index] )	mFontStyles[index] = new BitmapFontStyle( index, textures, fontsXml, sizes );
			// ajouter les tailles de font au BitmapFontStyle
			else						mFontStyles[index].addMultipleSizes( textures, fontsXml, sizes );
			
			// si le helperImage n'existe pas encore on le crée
			if( !mHelperImage )			mHelperImage 	= new Image( textures[0] );
			// si eucune taille de base n'est définie on prend la premiere du tableau
			if( _baseSize == -1 )		_baseSize 		= sizes[0];
			// si le style de base n'est pas encore défini, on prend le style actuel
			if( _baseStyle == -1 )		_baseStyle 		= index;
		}
		
		/** 
		 * Add one size for this font
		 * @param texture the texture of the font size to add
		 * @param xlm the xml vector of the font size to add
		 * @param size the font size to add
		 * @param bold point out if is a bold font
		 * @param italic point out if it is italic texture
		 **/
		public function add( texture:Texture, xml:XML, size:Number, bold:Boolean = false, italic:Boolean = false ):void
		{
			// récuperer l'index du style actuel
			var index:int = BitmapFontStyle.REGULAR;
			if( bold && italic ) 	index = BitmapFontStyle.BOLD_ITALIC;	
			else if( bold )			index = BitmapFontStyle.BOLD;
			else if( italic )		index = BitmapFontStyle.ITALIC;
			
			// créer le BitmapFontStyle pour le style si il n'existe pas encore
			if( !mFontStyles[index] )	mFontStyles[index] = new BitmapFontStyle( index, new <Texture>[texture], new <XML>[xml], new <Number>[size] );
			// ajouter la taille de font au BitmapFontStyle
			else						mFontStyles[index].add( texture, xml, size );
			
			// si le helperImage n'existe pas encore on le crée
			if( !mHelperImage )			mHelperImage 	= new Image( texture );
			// si eucune taille de base n'est définie on prend la taille actuelle
			if( _baseSize == -1 )		_baseSize 		= size;
			// si le style de base n'est pas encore défini, on prend le style actuel
			if( _baseStyle == -1 )		_baseStyle 		= index;
		}
		
		/** Dispose the associated BitmapFontStyle's */
		public function dispose():void
		{
			for( var i:int = 0; i<BitmapFontStyle.NUM_STYLES; ++i )	
			{
				if( mFontStyles[i] ) mFontStyles[i].dispose();
			}
			mFontStyles.fixed 	= false;
			mFontStyles.length 	= 0;
			mFontStyles 		= null;
		}
		
		
		/** 
		 * Fill the QuadBatch with text, no reset will be call on the QuadBatch
		 * @param quadBatch the QuadBatch to fill
		 * @param width container width
		 * @param height container height
		 * @param text the text String
		 * @param fontSizes (default null->base size) the array containing the size by char. (if shorter than the text, the last value is used for the rest)
		 * @param styles (default null->base style) the array containing the style by char. (if shorter than the text, the last value is used for the rest)
		 * @param colors (default null->0xFFFFFF) the array containing the colors by char, no tint -> 0xFFFFFF (if shorter than the text, the last value is used for the rest) 
		 * @param hAlign (default center) horizontal align rule
		 * @param vAlign (default center) vertical align rule
		 * @param autoScale (default true) if true the text will be reduced for fiting the container size (if smaller font size are available)
		 * @param kerning (default true) true if you want to use kerning
		 * @param resizeQuad (default false) if true, the Quad can be bigger tahn width, height if the texte cannot fit. 
		 * @param keepDatas (default null) don't delete the Vector.<CharLocation> at the end if a subclass need it.
		 * @param autoCR (default true) do auto line break or not.
		 **/
		public function fillQuadBatch(quadBatch:QuadBatch, width:Number, height:Number, text:String,
									  fontSizes:Array = null, styles:Array = null, colors:Array = null, 
									  hAlign:String="center", vAlign:String="center",      
									  autoScale:Boolean=true, 
									  kerning:Boolean=true, resizeQuad:Boolean = false, keepDatas:Object = null, autoCR:Boolean = true ):void
		{
			// découper le tableau de couleur pour ignorer les caracteres a remplacer par des emotes
			if( _emotesTxt )
			{
				for( var i:int = text.length-1; i>=0; --i )
				{
					for( var e:int = 0; e<_emotesTxt.length; ++e )
					{
						if( text.substr(i,_emotesTxt[e].length) == _emotesTxt[e] )
						{
							colors.splice(i,_emotesTxt[e].length-1);
							break;
						}
					}
				}
			}
			
			// générer le tableau de CharLocation
			var charLocations	:Vector.<CharLocation> 	= arrangeChars( width, height, text, fontSizes.concat(), styles.concat(), hAlign, vAlign, autoScale, kerning, resizeQuad, autoCR );
			
			// cas foireux pour le texte qui apparait mots à mots
			if( keepDatas )		keepDatas.loc = charLocations;
			if( !quadBatch )	return;
			
			// récupérer le nombre de caractères à traiter
			var numChars		:int 					= charLocations.length;
			
			// forcer le tint = true pour pouvoir avoir plusieurs couleur de texte
			mHelperImage.alpha = 0.9999;
			
			// si le tableau de couleur est vide ou null, on met du 0xFFFFFF par défaut (0xFFFFFF -> no modif)
			if( !colors || colors.length == 0 )	colors = [0xFFFFFF];
			
			// limitation du nombre d'images par QuadBatch 
			if( numChars > 8192 )	throw new ArgumentError("Bitmap Font text is limited to 8192 characters.");
			
			// parcourir les caractères pour les placer sur le QuadBatch
			for( i=0; i<numChars; ++i )
			{
				if( !charLocations[i] )
				{
					continue;
				}
				
				if( charLocations[i].doTint )
				{
					var color:*;
					// récupérer la couleur du caractère et colorer l'image
					if( i < colors.length )
					{
						color = colors[i];
					}
					else
					{
						color = colors[colors.length-1];
					}
					
					if( color is Array )
					{
						mHelperImage.setVertexColor(0, color[0]);
						mHelperImage.setVertexColor(1, color[1]);
						mHelperImage.setVertexColor(2, color[2]);
						mHelperImage.setVertexColor(3, color[3]);
					}
					else
					{
						mHelperImage.color = color;
					}
				}
				else
				{
					mHelperImage.color = 0xFFFFFF;
				}
				
				// récupérer le CharLocation du caractère actuel
				var charLocation:CharLocation = charLocations[i];
				// appliquer la texture du caractere à l'image
				mHelperImage.texture = charLocation.char.texture;
				// réajuster al taille de l'image pour la nouvelle texture
				mHelperImage.readjustSize();
				// placer l'image
				mHelperImage.x = charLocation.x;
				mHelperImage.y = charLocation.y;
				// scaler l'image
				mHelperImage.scaleX = mHelperImage.scaleY = charLocation.scale;
				// ajouter l'image au QuadBatch
				quadBatch.addImage( mHelperImage );
				
				if( !keepDatas )
				{
					// on retourne le charLocation dans la poule
					returnCharLoc( charLocations[i] );
					charLocations[i] = null;
				}
			}
			
			if( !keepDatas )	returnVCharLoc( charLocations );
		}
		
		/** Arranges the characters of a text inside a rectangle, adhering to the given settings. 
		 *  Returns a Vector of CharLocations. */
		private function arrangeChars( width:Number, height:Number, text:String, fontSizes:Array = null, styles:Array = null, hAlign:String="center", vAlign:String="center", autoScale:Boolean=true, kerning:Boolean=true, resizeQuad:Boolean = false, autoCR:Boolean = true ):Vector.<CharLocation>
		{
			// si pas de texte on renvoi un tableau vide
			if( text == null || text.length == 0 ) 		return getVCharLoc();
			
			// aucun style définit, on force le style de base
			if( !styles || styles.length == 0 ) 		styles 		= [_baseStyle];
			
			// aucune taille définie, on force la taille de base
			if( !fontSizes || fontSizes.length == 0 )	fontSizes 	= [_baseSize];
			
			// trouver des tailles adaptées en fonction du scale global de l'application
			if( _globalScale != 1 )						fontSizes = _getSizeForActualScale( fontSizes, styles );
			
			// passe a true une fois qu'on a fini de rendre le texte
			var finished			:Boolean = false;
			// une charLocation pour remplir le vecteur de lignes
			var charLocation		:CharLocation;
			// le nombre de caracteres à traiter
			var numChars			:int;
			// la hauteur de ligne pour le plus gros caractère
			var biggestLineHeight	:int;
			// la taille de font du caractere actuel
			var sizeActu			:int;
			// la style de font du caractere actuel
			var styleActu			:int;
			// la largeur du conteneur
			var containerWidth		:Number = width / _currentScale;
			// la hauteur du conteneur
			var containerHeight		:Number = height / _currentScale;
			// la largeur du conteneur
			/*var containerWidth		:Number = width;
			// la hauteur du conteneur
			var containerHeight		:Number = height;*/
			
			while( !finished )
			{
				// init/reset le tableau de lignes
				lines.length 		= 0;
				linesSizes.length 	= 0;
				
				// récuperer la hauteur du plus haut caractere savoir si il rentre dans la zone ou pas
				biggestLineHeight 	= Math.ceil( _getBiggestLineHeight( fontSizes, styles ) );
				
				// si le plus gros caractere rentre en hauteur dans la zone spécifiée
				if( resizeQuad || biggestLineHeight <= containerHeight )
				{
					var lastWhiteSpace	:int 		= -1;
					var lastCharID		:int 		= -1;
					var currentX		:Number 	= 0;
					var currentY		:Number 	= 0;
					var currentLine		:Vector.<CharLocation> = getVCharLoc();//new <CharLocation>[];
					var currentMaxSize	:int = 0;
					var realMaxSize		:int = 0;
					
					numChars = text.length;
					for( var i:int=0; i<numChars; ++i )
					{
						// récupérer la taille actuelle
						if( i < fontSizes.length )		sizeActu 	= fontSizes[i];
						// récupérer le syle actuel
						if( i < styles.length )			styleActu 	= styles[i];
						// style erroné on prend le stle de base
						if( styleActu > BitmapFontStyle.NUM_STYLES || !mFontStyles[styleActu] )	styleActu = _baseStyle;
						
						var lineHeight:int = mFontStyles[styleActu].getLineHeightForSize(sizeActu);
						if( lineHeight > currentMaxSize )			currentMaxSize 	= lineHeight;
						if( currentMaxSize > realMaxSize )			realMaxSize 	= currentMaxSize;
						
						var isEmote		:Boolean 	= false;
						// c'est une nouvelle ligne donc la ligne n'est surrement pas finie
						var lineFull	:Boolean 	= false;
						// récupérer le CharCode du caractère actuel
						var charID		:int 		= text.charCodeAt(i);
						// récupérer le BitmapChar du caractère actuel
						var char		:BitmapChar = mFontStyles[styleActu].getCharForSize( charID, sizeActu );
						// le caractère n'est pas disponible, on remplace par un espace
						if( char == null )
						{
							if( charID != CHAR_NEWLINE && charID != CHAR_CARRIAGE_RETURN )	charID = CHAR_SPACE;
							char = mFontStyles[styleActu].getCharForSize( CHAR_SPACE, sizeActu );
						}
						
						if( _emotesTxt )
						{
							for( var e:int = 0; e<_emotesTxt.length; ++e )
							{
								if( text.substr(i,_emotesTxt[e].length) == _emotesTxt[e] )
								{
									char = _emotesTextures[e];
									i += _emotesTxt[e].length-1;
									isEmote = true;
									break;
								}
							}
							if( isEmote && char.height > realMaxSize )
							{
								// si l'emote est plus grand on descend tous les caracteres de la ligne
								var dif:int = ( (char.height - realMaxSize) >> 1 )+2;
								currentY += dif;
								for( var a:int = 0; a<currentLine.length; ++a )
								{
									currentLine[a].y += dif;
								}
								realMaxSize = char.height;
							}
						}
						
						// retour à la ligne
						if( charID == CHAR_NEWLINE || charID == CHAR_CARRIAGE_RETURN )		lineFull = true;
						else
						{
							// on enregistre le placement du dernier espace
							if( charID == CHAR_SPACE || charID == CHAR_TAB )	lastWhiteSpace = i;
							// application du kerning si activé
							if( kerning ) 										currentX += char.getKerning(lastCharID);
							
							// créer un CharLocation ou le récupérer dans la pool
							charLocation 			= getCharLoc(char);
							charLocation.size 		= sizeActu;
							charLocation.style 		= styleActu;
							charLocation.isEmote 	= isEmote;
							
							// définir la position du caractère en x
							charLocation.x 			= currentX + char.xOffset;
							// définir la position du caractère en y, on y rajoute (la hauteur de ligne du plus grand caractere)-(la hauteur de ligne du caractere actuel)
							charLocation.y 			= currentY + char.yOffset;// + ( biggestLineHeight - mFontStyles[styleActu].getLineHeightForSize(sizeActu) );
							// si c'est un emote, on le centre
							if( isEmote )	charLocation.y = currentY + char.yOffset - ( (char.height - lineHeight) >> 1 );
							// définir si on doit tinter ou non le texte en fonction de si c'est une emote
							charLocation.doTint = !isEmote;
							// on ajoute le caractère au tableau
							currentLine.push( charLocation );
							
							// on met a jour la position x du prochain caractère si ce n'est pas le premier espace d'une ligne
							if( currentLine.length != 1 || charID != CHAR_SPACE )	currentX += char.xAdvance;
							
							// on enregistre le CharCode du caractère
							lastCharID = charID;
							
							// new line
							//if( charID == CHAR_NEWLINE || charID == CHAR_CARRIAGE_RETURN )	lineFull = true;
							// fin de ligne car dépassement de la largeur du conteneur
							if( (!resizeQuad || autoCR) && charLocation.x + char.width > containerWidth )
							{
								// si autoscale est a true on ne doit pas couper le mot en 2
								if( !autoCR || (autoScale && lastWhiteSpace == -1) )		break;
								
								// si on a eu un espace on va couper apres le dernier espace sinon on coupe à lindex actuel
								var numCharsToRemove	:int = lastWhiteSpace == -1 ? 1 : i - lastWhiteSpace + 1;
								var removeIndex			:int = currentLine.length - numCharsToRemove;
								
								// couper la ligne
								var temp:Vector.<CharLocation> = getVCharLoc();
								var l:int = currentLine.length;
								
								for( var t:int = 0; t<l; ++t )
								{
									if( t < removeIndex || t >= removeIndex+numCharsToRemove )	temp.push( currentLine[t] );
									else														
									{
										returnCharLoc( currentLine[t] );
										currentLine[t] = null;
									}
								}
								returnVCharLoc( currentLine );
								currentLine = temp;
								
								// il faut baisser la taille de la font -> on arrete la
								if( currentLine.length == 0 )	
								{
									returnVCharLoc( currentLine );
									break;
								}
								
								i -= numCharsToRemove;
								
								lineFull = true;
								// si le prochain caractere est un saut de ligne, on l'ignore
								if( text.charCodeAt(i+1) == CHAR_CARRIAGE_RETURN || text.charCodeAt(i+1) == CHAR_NEWLINE )	
								{
									++i;
								}
							}
						}
						
						// fin du texte
						if( i == numChars - 1 )
						{
							lines.push( currentLine );
							linesSizes.push( currentMaxSize );
							//currentMaxSize = 0;
							finished = true;
						}
						// fin de ligne
						else if( lineFull )
						{
							currentLine.push(null);
							lines.push( currentLine );
							linesSizes.push( currentMaxSize );
							
							// le dernier caractere de la ligne est un espace
							//if( lastWhiteSpace == i )	currentLine.pop();
							
							// on a la place de mettre une nouvelle ligne
							if( resizeQuad || currentY + 2*currentMaxSize + _lineSpacing <= containerHeight )
							{
								// créer un tableau pour la nouvelle ligne
								currentLine = getVCharLoc();//new <CharLocation>[];
								// remettre le x à 0
								currentX = 0;
								// mettre le y à la prochaine ligne
								currentY += realMaxSize+_lineSpacing;
								// reset lastWhiteSpace index
								lastWhiteSpace = -1;
								// reset lastCharID vu que le kerning ne va pas s'appliquer entre 2 lignes
								lastCharID = -1;
								// reset la taille max pour la ligne
								currentMaxSize = realMaxSize = 0;
							}
							else
							{
								// il faut baisser la taille de la font -> on arrete la
								break;
							}
						}
					} // for each char
				} // if (mLineHeight <= containerHeight)
				
				// si l'autoscale est activé et que le texte ne rentre pas dans la zone spécifié, on réduit la taille de la police
				if( autoScale && !finished && _reduceSizes(fontSizes, styles) )
				{
					// on reset les lignes et on retourne les charLocation dans la poule
					var len:int = lines.length;
					var len2:int;
					for ( i = 0; i<len; ++i )
					{
						len2 = lines[i].length;
						for( var j:int = 0; j<len2; ++j )
						{
							if( lines[i][j] )	
							{
								returnCharLoc(lines[i][j]);
								lines[i][j] = null;
								//lines[i][j].reset;
								//mCharLocationPool.push(lines[i][j]);
							}
						}
						returnVCharLoc(lines[i]);
						//lines[i].length = 0;
					}
					lines.length = 0;
					//longestLineWidth = 0;
				}
				else
				{
					// on peut rien y faire on y arrivera pas c'est fini
					finished = true; 
				}
				
			} // while (!finished)
			
			// le tableau de positionnement final des caractères
 			var finalLocations	:Vector.<CharLocation> 	= getVCharLoc();//new <CharLocation>[];
			// le nombre de lignes
			var numLines		:int 					= lines.length;
			// le y max du texte
			var bottom			:Number 				= currentY + currentMaxSize;//biggestLineHeight;
			// l'offset y
			var yOffset			:int 					= 0;
			// la ligne à traiter
			var line			:Vector.<CharLocation>;
			
			// calculer l'offset y en fonction de la rêgle d'alignement vertical 
			if( vAlign == VAlign.BOTTOM )      	yOffset =  containerHeight - bottom;
			else if( vAlign == VAlign.CENTER ) 	yOffset = (containerHeight - bottom) / 2;
			
			if( yOffset<0 )	yOffset = 0;
			
			// la taille de la ligne la plus longue utile pour les LEFT_CENTERED et RIGHT_CENTERED
			var longestLineWidth:Number = 0;
			
			if( hAlign == HTMLTextField.RIGHT_CENTERED || hAlign == HTMLTextField.LEFT_CENTERED )
			{
				for( i=0; i<numLines; ++i )
				{
					// récupérer la ligne actuelle
					line 		= lines[i];
					// récupérer le nombre de caractères sur la ligne
					numChars 	= line.length;
					// si ligne vide -> on passe à la suivante
					if( numChars == 0 ) 	continue;
					
					for( j = numChars-1;j>=0; --j )
					{
						if( !lines[i][j] || lines[i][j].char.charID == CHAR_SPACE )		continue;
						
						if( lines[i][j].x+lines[i][j].char.width > longestLineWidth )	
							longestLineWidth = lines[i][j].x+lines[i][j].char.width;
						
						break;
					}
				}
			}
			
			// parcourir les lignes
			for( var lineID:int=0; lineID<numLines; ++lineID )
			{
				// récupérer la ligne actuelle
				line 		= lines[lineID];
				// récupérer le nombre de caractères sur la ligne
				numChars 	= line.length;
				
				// si ligne vide -> on passe à la suivante
				if( numChars == 0 ) continue;
				
				// l'offset x
				var xOffset			:int 			= 0;
				// la position du dernier caractère de la ligne
				j = 1;
				var lastLocation	:CharLocation 	= line[line.length-j];
				while( lastLocation == null && line.length-j >= 0)
				{
					lastLocation = line[line.length-j++];
				}
				// le x max de la ligne
				var right			:Number 		= lastLocation ? lastLocation.x - lastLocation.char.xOffset + lastLocation.char.xAdvance : 0;
				
				// calculer l'offset x en fonction de la règle d'alignement horizontal
				if( hAlign == HAlign.RIGHT )       					xOffset =  containerWidth - right;
				else if( hAlign == HAlign.CENTER ) 					xOffset = (containerWidth - right) / 2;
				else if( hAlign == HTMLTextField.RIGHT_CENTERED ) 	xOffset = longestLineWidth + (containerWidth - longestLineWidth) / 2 - right;
				else if( hAlign == HTMLTextField.LEFT_CENTERED ) 	xOffset = (containerWidth - longestLineWidth) / 2;
				
				// parcourir les caractères
				for( var c:int=0; c<numChars; ++c )
				{
					// récupérer le CharLocation
					charLocation 		= line[c];
					if( charLocation )
					{
						// appliquer l'offset x et le _globalScale à la positon x du caractère
						//charLocation.x 		= _currentScale * (charLocation.x + xOffset);
						charLocation.x = charLocation.x + xOffset;
						
						if( !charLocation.isEmote )	
							charLocation.y += linesSizes[lineID] - mFontStyles[charLocation.style].getLineHeightForSize(charLocation.size);
						
						// appliquer l'offset y et le _globalScale à la positon y du caractère
						charLocation.y 		= _currentScale * (charLocation.y + yOffset );
						//charLocation.y 		= charLocation.y + yOffset;
						// appliquer le globalScale au scale du caractère
						charLocation.scale 	= _currentScale;
						//charLocation.scale 	= 1;
						// ajouter le caractere au tableau
						finalLocations.push(charLocation);
					}
					line[c] = null;
				}
				returnVCharLoc( line );
			}
			
			lines.length 		= 0;
			linesSizes.length 	= 0;
			
			return finalLocations;
		}
		
		/** retourne un tableau avec les nouvelles tailles à appliquer en fonction du scale général de l'application **/
		[Inline]
		private final function _getSizeForActualScale( sizes:Array, styles:Array ):Array
		{
			// le scale actuel de starling
			var scale		:Number = 1/_globalScale;
			// la valeur max à retourner
			var newSizes	:Array = [];
			// la taille de ligne pour le caractere actuel
			var lineActu	:Number;
			// la taille de font du caractere actuel
			var sizeActu	:int;
			// la style de font du caractere actuel
			var styleActu	:int;
			
			// récupérer la taille du plus grand des tableaux
			var len			:int = sizes.length;
			
			for( var i:int = 0; i<len; ++i )
			{
				// récupérer la taille actuelle
				sizeActu = sizes[i];
				// récupérer le syle actuel
				if( i < styles.length )			styleActu = styles[i];
				// style erroné on prend le stle de base
				if( styleActu > BitmapFontStyle.NUM_STYLES || !mFontStyles[styleActu] )	styleActu = _baseStyle;
				// récupérer la hauteur de ligne pour ce style et cette taille
				lineActu = mFontStyles[styleActu].getLineHeightForSize(sizeActu) * scale;
				// trouver une taille de font correspondante
				newSizes[i] = mFontStyles[styleActu].getSizeForLineHeight(lineActu);
				
				if( mFontStyles[styleActu].getLineHeightForSize(newSizes[i]) > lineActu )
				{
					_currentScale = 1;
					return sizes;
				}
			}
			
			// mettre à jour le scale global
			_currentScale = 1/scale;
			
			// retourner les nouvelles tailles et le nouveau scale
			return newSizes;
		}
		
		/** return the biggest line height **/
		[Inline]
		private final function _getBiggestLineHeight( sizes:Array, styles:Array ):Number
		{
			// la valeur max à retourner
			var max			:Number = 0;
			// la taille de ligne pour le caractere actuel
			var lineActu	:Number;
			// la taille de font du caractere actuel
			var sizeActu	:int;
			// la style de font du caractere actuel
			var styleActu	:int;
			
			// récupérer la taille du plus grand des tableaux
			var len			:int = sizes.length;
			if( styles.length > len )	len = styles.length;
			
			for( var i:int = 0; i<len; ++i )
			{
				// récupérer la taille actuelle
				if( i < sizes.length )			sizeActu 	= sizes[i];
				// récupérer le syle actuel
				if( i < styles.length )			styleActu 	= styles[i];
				
				// style erroné on prend le stle de base
				if( styleActu > BitmapFontStyle.NUM_STYLES || !mFontStyles[styleActu] )	styleActu = _baseStyle;
				
				// récupérer la hauteur de ligne pour ce style et cette taille
				lineActu = mFontStyles[styleActu].getLineHeightForSize(sizeActu);
				// si la valeur est plus grande on met à jour max
				if( lineActu > max )	max = lineActu;
			}
			
			// retourner la valeur max
			return max;
		}
		
		/** reduce the size of all items in the array **/
		[Inline]
		private final function _reduceSizes( sizes:Array, styles:Array ):Boolean
		{
			// la taille d'origine avant d'essayer de reduire
			var orig		:Number;
			// variable pour savoir si on a pu reduire ou pas des caracteres selon la disponibilité des fonts intégrés
			var reduced		:Boolean = false;
			// la style de font du caractere actuel
			var styleActu	:int;
			// récupérer la taille du tableau de tailles
			var len			:int = sizes.length;
			
			for( var i:int = 0; i<len; ++i )
			{
				// récupérer le syle actuel
				if( i < styles.length )			styleActu = styles[i];
				// style erroné on prend le stle de base
				if( styleActu > BitmapFontStyle.NUM_STYLES || !mFontStyles[styleActu] )	styleActu = _baseStyle;
				
				// enregistrer la valeur avant reduction pour pouvoir vérifier si une taille plus petite était disponible ou pas
				orig = sizes[i];
				// recuperer une taille en dessous ou la meme
				sizes[i] = mFontStyles[styleActu].getSmallerSize( sizes[i] );
				
				// passer reduced a true si on a pu réduire la taille de la font
				if( orig > sizes[i] )	reduced = true;
			}
			
			// retourner l'état de reduction de la font
			return reduced;
		}
		
		/** The name of the font as it was parsed from the font file. */
		public function get name():String { return mName; }
		
		/** The smoothing filter that is used for the texture. */ 
		public function get smoothing():String { return mHelperImage.smoothing; }
		public function set smoothing(value:String):void { mHelperImage.smoothing = value; } 
		
		public function getAvailableSizesForStyle( style:int ):Vector.<Number>
		{
			return mFontStyles[style] ? mFontStyles[style].availableSizes : null;
		}
		
		private var _lineSpacing:int = 0;
		public function set lineSpacing( value:int ):void
		{
			_lineSpacing = value;
		}
	}
}