package iron.data;

import kha.graphics4.PipelineState;
import kha.graphics4.ConstantLocation;
import kha.graphics4.TextureUnit;
import kha.graphics4.VertexStructure;
import kha.graphics4.VertexData;
import kha.graphics4.StencilAction;
import kha.graphics4.CompareMode;
import kha.graphics4.CullMode;
import kha.graphics4.BlendingOperation;
import kha.graphics4.BlendingFactor;
import kha.graphics4.TextureAddressing;
import kha.graphics4.TextureFilter;
import kha.graphics4.MipMapFilter;
import iron.data.SceneFormat;

class ShaderData extends Data {

	public var name:String;
	public var raw:TShaderData;

	var structure:VertexStructure;
	var structureLength = 0;
	var inst = false;

	public var contexts:Array<ShaderContext> = [];

	public function new(raw:TShaderData, overrideContext:TShaderOverride, done:ShaderData->Void) {
		super();

		this.raw = raw;
		this.name = raw.name;

		parseVertexStructure();

		for (c in raw.contexts) {
			// Render path might not use all shaders contexts, skip context if shader is not found
			var fragName = StringTools.replace(c.fragment_shader, ".", "_");
			if (Reflect.field(kha.Shaders, fragName) == null) {
				continue;
			}
			
			contexts.push(new ShaderContext(c, structure, inst, overrideContext));
		}

		done(this);
	}

	public static function parse(file:String, name:String, overrideContext:TShaderOverride, done:ShaderData->Void) {
		Data.getSceneRaw(file, function(format:TSceneFormat) {
			var raw:TShaderData = Data.getShaderRawByName(format.shader_datas, name);
			if (raw == null) {
				trace('Shader data "$name" not found!');
				done(null);
			}
			new ShaderData(raw, overrideContext, done);
		});
	}

	public function delete() {
		for (c in contexts) c.delete();
	}

	function sizeToVD(size:Int):VertexData {
		if (size == 1) return VertexData.Float1;
		else if (size == 2) return VertexData.Float2;
		else if (size == 3) return VertexData.Float3;
		else if (size == 4) return VertexData.Float4;
		return null;
	}
	function parseVertexStructure() {
		structure = new VertexStructure();
		for (vs in raw.vertex_structure) {
			if (vs.name == 'off') {
				inst = true;
				continue;
			}

			structure.add(vs.name, sizeToVD(vs.size));
			structureLength += vs.size;
		}
	}

	public function getContext(name:String):ShaderContext {
		for (c in contexts) {
			if (c.raw.name.substr(0, name.length) == name) return c;
		}
		return null;
	}
}

class ShaderContext {
	public var raw:TShaderContext;

	public var pipeState:PipelineState;
	public var constants:Array<ConstantLocation> = [];
	public var textureUnits:Array<TextureUnit> = [];

	public function new(raw:TShaderContext, structure:VertexStructure, inst = false, overrideContext:TShaderOverride = null) {
		this.raw = raw;

		pipeState = new PipelineState();

		// Instancing
		if (inst) {
			var instStruct = new VertexStructure();
			instStruct.add("off", VertexData.Float3);
			pipeState.inputLayout = [structure, instStruct];
		}
		// Regular
		else {
			pipeState.inputLayout = [structure];
		}
		
		// Depth
		pipeState.depthWrite = raw.depth_write;
		pipeState.depthMode = getCompareMode(raw.compare_mode);
		
		// Stencil
		if (raw.stencil_mode != null) {
			if (raw.stencil_mode == "always")
				pipeState.stencilMode = CompareMode.Always;
			else if (raw.stencil_mode == "equal")
				pipeState.stencilMode = CompareMode.Equal;
			else if (raw.stencil_mode == "not_equal")
				pipeState.stencilMode = CompareMode.NotEqual;
		}
		if (raw.stencil_pass != null) {
			if (raw.stencil_pass == "replace")
				pipeState.stencilBothPass = StencilAction.Replace;
			else if (raw.stencil_pass == "keep")
				pipeState.stencilBothPass = StencilAction.Keep;
		}
		if (raw.stencil_fail != null && raw.stencil_fail == "keep") {
			pipeState.stencilDepthFail = StencilAction.Keep;
			pipeState.stencilFail = StencilAction.Keep;
		}
		if (raw.stencil_reference_value != null) {
			pipeState.stencilReferenceValue = raw.stencil_reference_value;
		}	
		// pipeState.stencilReadMask = raw.stencil_read_mask;
		// pipeState.stencilWriteMask = raw.stencil_write_mask;

		// Cull
		pipeState.cullMode = getCullMode(raw.cull_mode);
		
		// Blending
		if (raw.blend_source != null) pipeState.blendSource = getBlendingFactor(raw.blend_source);
		if (raw.blend_destination != null) pipeState.blendDestination = getBlendingFactor(raw.blend_destination);
		if (raw.blend_operation != null) pipeState.blendOperation = getBlendingOperation(raw.blend_operation);
		if (raw.alpha_blend_source != null) pipeState.alphaBlendSource = getBlendingFactor(raw.alpha_blend_source);
		if (raw.alpha_blend_destination != null) pipeState.alphaBlendDestination = getBlendingFactor(raw.alpha_blend_destination);
		if (raw.alpha_blend_operation != null) pipeState.alphaBlendOperation = getBlendingOperation(raw.alpha_blend_operation);

		// Color write mask
		if (raw.color_write_red != null) pipeState.colorWriteMaskRed = raw.color_write_red;
		if (raw.color_write_green != null) pipeState.colorWriteMaskGreen = raw.color_write_green;
		if (raw.color_write_blue != null) pipeState.colorWriteMaskBlue = raw.color_write_blue;
		if (raw.color_write_alpha != null) pipeState.colorWriteMaskAlpha = raw.color_write_alpha;

		// Shaders
		pipeState.fragmentShader = Reflect.field(kha.Shaders, StringTools.replace(raw.fragment_shader, ".", "_"));
		pipeState.vertexShader = Reflect.field(kha.Shaders, StringTools.replace(raw.vertex_shader, ".", "_"));

		if (raw.geometry_shader != null) {
			pipeState.geometryShader = Reflect.field(kha.Shaders, StringTools.replace(raw.geometry_shader, ".", "_"));
		}
		if (raw.tesscontrol_shader != null) {
			pipeState.tessellationControlShader = Reflect.field(kha.Shaders, StringTools.replace(raw.tesscontrol_shader, ".", "_"));
		}
		if (raw.tesseval_shader != null) {
			pipeState.tessellationEvaluationShader = Reflect.field(kha.Shaders, StringTools.replace(raw.tesseval_shader, ".", "_"));
		}

		// Override specified values
		if (overrideContext != null) {
			if (overrideContext.cull_mode != null) {
				pipeState.cullMode = getCullMode(overrideContext.cull_mode);
			}
		}

		pipeState.compile();

		if (raw.constants != null) {
			for (c in raw.constants) addConstant(c);
		}

		if (raw.texture_units != null) {
			for (tu in raw.texture_units) addTexture(tu);
		}
	}

	inline function deleteShader(shader:Dynamic) {
#if sys_krom
		if (shader.shader == null) return;
#end	
		shader.delete();
	}

	public function delete() {
		if (pipeState.fragmentShader != null) deleteShader(pipeState.fragmentShader);
		if (pipeState.vertexShader != null) deleteShader(pipeState.vertexShader);
		if (pipeState.geometryShader != null) deleteShader(pipeState.geometryShader);
		if (pipeState.tessellationControlShader != null) deleteShader(pipeState.tessellationControlShader);
		if (pipeState.tessellationEvaluationShader != null) deleteShader(pipeState.tessellationEvaluationShader);
		pipeState.delete();
	}

	function getCompareMode(s:String):CompareMode {
		switch(s) {
		case "always": return CompareMode.Always;
		case "never": return CompareMode.Never;
		case "less": return CompareMode.Less;
		case "less_equal": return CompareMode.LessEqual;
		case "greater": return CompareMode.Greater;
		case "greater_equal": return CompareMode.GreaterEqual;
		case "equal": return CompareMode.Equal;
		case "not_equal": return CompareMode.NotEqual;
		default: return CompareMode.Less;
		}
	}

	function getCullMode(s:String):CullMode {
		switch(s) {
		case "none": return CullMode.None;
		case "clockwise": return CullMode.Clockwise;
		default: return CullMode.CounterClockwise;
		}			
	}

	function getBlendingOperation(s:String):BlendingOperation {
		switch(s) {
		case "add": return BlendingOperation.Add;
		case "substract": return BlendingOperation.Subtract;
		case "reverse_substract": return BlendingOperation.ReverseSubtract;
		case "min": return BlendingOperation.Min;
		case "max": return BlendingOperation.Max;
		default: return BlendingOperation.Add;
		}
	}
	
	function getBlendingFactor(s:String):BlendingFactor {
		switch(s) {
		case "blend_one": return BlendingFactor.BlendOne;
		case "blend_zero": return BlendingFactor.BlendZero;
		case "source_alpha": return BlendingFactor.SourceAlpha;
		case "destination_alpha": return BlendingFactor.DestinationAlpha;
		case "inverse_source_alpha": return BlendingFactor.InverseSourceAlpha;
		case "inverse_destination_alpha": return BlendingFactor.InverseDestinationAlpha;
		case "source_color": return BlendingFactor.SourceColor;
		case "destination_color": return BlendingFactor.DestinationColor;
		case "inverse_source_color": return BlendingFactor.InverseSourceColor;
		case "inverse_destination_color": return BlendingFactor.InverseDestinationColor;
		default: return BlendingFactor.Undefined;
		}
	}

	function getTextureAddresing(s:String):TextureAddressing {
		switch(s) {
		case "repeat": return TextureAddressing.Repeat;
		case "mirror": return TextureAddressing.Mirror;
		default: return TextureAddressing.Clamp;
		}
	}

	function getTextureFilter(s:String):TextureFilter {
		switch(s) {
		case "point": return TextureFilter.PointFilter;
		case "linear": return TextureFilter.LinearFilter;
		default: return TextureFilter.AnisotropicFilter;
		}	
	}

	function getMipmapFilter(s:String):MipMapFilter {
		switch(s) {
		case "no": return MipMapFilter.NoMipFilter;
		case "point": return MipMapFilter.PointMipFilter;
		default: return MipMapFilter.LinearMipFilter;
		}
	}

	function addConstant(c:TShaderConstant) {
		constants.push(pipeState.getConstantLocation(c.name));
	}

	function addTexture(tu:TTextureUnit) {
		var unit = pipeState.getTextureUnit(tu.name);
		textureUnits.push(unit);
	}
	
	public function setTextureParameters(g:kha.graphics4.Graphics, unitIndex:Int, tex:TBindTexture) {
		// This function is called for samplers set using material context		
		var unit = textureUnits[unitIndex];
		g.setTextureParameters(unit,
			tex.u_addressing == null ? TextureAddressing.Repeat : getTextureAddresing(tex.u_addressing),
			tex.v_addressing == null ? TextureAddressing.Repeat : getTextureAddresing(tex.v_addressing),
			tex.min_filter == null ? TextureFilter.LinearFilter : getTextureFilter(tex.min_filter),
			tex.mag_filter == null ? TextureFilter.LinearFilter : getTextureFilter(tex.mag_filter),
			tex.mipmap_filter == null ? MipMapFilter.NoMipFilter : getMipmapFilter(tex.mipmap_filter));
	}
}
