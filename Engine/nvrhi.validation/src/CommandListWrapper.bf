using System;
using nvrhi.rt;
using System.Collections;
namespace nvrhi.validation
{
	class CommandListWrapper : RefCounter<ICommandList>
	{
		public this(DeviceWrapper device, ICommandList commandList, bool isImmediate, CommandQueue queueType)
		{
			m_CommandList = commandList;
			m_Device = device;
			m_MessageCallback = device.getMessageCallback();
			m_IsImmediate = isImmediate;
			m_type = queueType;
		}

		private static char8* CommandListStateToString(CommandListState state)
		{
			switch (state)
			{
			case CommandListState.INITIAL:
				return "INITIAL";
			case CommandListState.OPEN:
				return "OPEN";
			case CommandListState.CLOSED:
				return "CLOSED";
			default:
				return "<INVALID>";
			}
		}

		private static char8* CommandQueueTypeToString(CommandQueue type)
		{
			switch (type)
			{
			case CommandQueue.Graphics:
				return "GRAPHICS";
			case CommandQueue.Compute:
				return "COMPUTE";
			case CommandQueue.Copy:
				return "COPY";
			case CommandQueue.Count: fallthrough;
			default:
				return "<INVALID>";
			}
		}

		protected CommandListHandle m_CommandList;
		protected RefCountPtr<DeviceWrapper> m_Device;
		protected IMessageCallback m_MessageCallback;
		protected bool m_IsImmediate;
		protected CommandQueue m_type;

		protected CommandListState m_State = CommandListState.INITIAL;
		protected bool m_GraphicsStateSet = false;
		protected bool m_ComputeStateSet = false;
		protected bool m_MeshletStateSet = false;
		protected bool m_RayTracingStateSet = false;
		protected GraphicsState m_CurrentGraphicsState;
		protected ComputeState m_CurrentComputeState;
		protected MeshletState m_CurrentMeshletState;
		protected nvrhi.rt.State m_CurrentRayTracingState;

		protected int m_PipelinePushConstantSize = 0;
		protected bool m_PushConstantsSet = false;

		protected void error(String messageText)
		{
			m_MessageCallback.message(MessageSeverity.Error, messageText);
		}
		protected void warning(String messageText)
		{
			m_MessageCallback.message(MessageSeverity.Warning, messageText);
		}

		protected bool requireOpenState()
		{
			if (m_State == CommandListState.OPEN)
				return true;

			String message = scope $"A command list must be opened before any rendering commands can be executed. Actual state: {CommandListStateToString(m_State)}.";
			error(message);

			return false;
		}
		protected bool requireExecuteState()
		{
			switch (m_State)
			{
			case CommandListState.INITIAL:
				error("Cannot execute a command list before it is opened and then closed");
				return false;
			case CommandListState.OPEN:
				error("Cannot execute a command list before it is closed");
				return false;
			case CommandListState.CLOSED:
			default:
				break;
			}

			m_State = CommandListState.INITIAL;
			return true;
		}
		protected bool requireType(CommandQueue queueType, char8* operation)
		{
			if ((int32)m_type > (int32)queueType)
			{
				String message = scope $"This command list has type {CommandQueueTypeToString(m_type)}, but the '{operation}' operation requires at least {CommandQueueTypeToString(queueType)}";
				error(message);

				return false;
			}

			return true;
		}
		protected ICommandList getUnderlyingCommandList() { return m_CommandList; }

		protected void evaluatePushConstantSize(nvrhi.BindingLayoutVector bindingLayouts)
		{
			m_PipelinePushConstantSize = 0;

			// Find the first PushConstants entry.
			// Assumes that the binding layout vector has been validated for duplicated push constants entries.

			for ( /*readonly ref*/var layout in ref bindingLayouts)
			{
				readonly BindingLayoutDesc* layoutDesc = layout.getDesc();

				if (layoutDesc == null) // bindless layouts have null desc
					continue;

				for ( /*readonly ref*/var item in ref layoutDesc.bindings)
				{
					if (item.type == ResourceType.PushConstants)
					{
						m_PipelinePushConstantSize = item.size;
						return;
					}
				}
			}
		}

		protected bool validatePushConstants(char8* pipelineType, char8* stateFunctionName)
		{
			if (m_PipelinePushConstantSize != 0 && !m_PushConstantsSet)
			{
				String message = scope $"""
				The {pipelineType} pipeline expects push constants ({m_PipelinePushConstantSize} bytes) that were not set.
				Push constants must be set after each call to {stateFunctionName}
			""";

				error(message);

				return false;
			}

			return true;
		}

		protected bool validateBindingSetsAgainstLayouts(StaticVector<BindingLayoutHandle, const c_MaxBindingLayouts> layouts, StaticVector<IBindingSet, const c_MaxBindingLayouts> sets)
		{
			if (layouts.Count != sets.Count)
			{
				String message = scope $"Number of binding sets provided ({sets.Count}) does not match the number of binding layouts in the pipeline ({layouts.Count})";
				error(message);
				return false;
			}

			bool anyErrors = false;

			for (int32 index = 0; index < int32(layouts.Count); index++)
			{
				if (sets[index] == null)
				{
					String message = scope $"Binding set in slot {index} is NULL";
					error(message);
					anyErrors = true;
					continue;
				}

				IBindingLayout setLayout = sets[index].getLayout();
				IBindingLayout expectedLayout = layouts[index];
				bool setIsBindless = (sets[index].getDesc() == null);
				bool expectedBindless = expectedLayout.getBindlessDesc() != null;

				if (!expectedBindless && setLayout != expectedLayout)
				{
					String message = scope $"Binding set in slot {index} does not match the layout in pipeline slot {index}";
					error(message);
					anyErrors = true;
				}

				if (expectedBindless && !setIsBindless)
				{
					String message = scope $"Binding set in slot {index} is regular while the layout expects a descriptor table";
					error(message);
					anyErrors = true;
				}
			}

			return !anyErrors;
		}

		protected bool validateBuildTopLevelAccelStruct(AccelStructWrapper wrapper, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags)
		{
			if (!wrapper.isTopLevel)
			{
				String message = scope $"Cannot perform buildTopLevelAccelStruct on a bottom-level AS {utils.DebugNameToString(wrapper.getDesc().debugName)}";
				error(message);
				return false;
			}

			if (numInstances > wrapper.maxInstances)
			{
				String message = scope $"Cannot build TLAS {utils.DebugNameToString(wrapper.getDesc().debugName)} with {numInstances} instances which is greater than topLevelMaxInstances  specified at creation ({wrapper.maxInstances})";
				error(message);
				return false;
			}

			if ((buildFlags & AccelStructBuildFlags.PerformUpdate) != 0)
			{
				if (!wrapper.allowUpdate)
				{
					String message = scope $"Cannot perform an update on TLAS {utils.DebugNameToString(wrapper.getDesc().debugName)} that was not created with the ALLOW_UPDATE flag";
					error(message);
					return false;
				}

				if (!wrapper.wasBuilt)
				{
					String message = scope $"Cannot perform an update on TLAS {utils.DebugNameToString(wrapper.getDesc().debugName)} before the same TLAS was initially built";
					error(message);
					return false;
				}

				if (wrapper.buildInstances != numInstances)
				{
					String message = scope $"Cannot perform an update on TLAS {utils.DebugNameToString(wrapper.getDesc().debugName)} with {numInstances} instances when this TLAS was built with {wrapper.buildInstances} instances";
					error(message);
					return false;
				}
			}

			return true;
		}


		// IResource implementation

		public override NativeObject getNativeObject(ObjectType objectType)
		{
			return m_CommandList.getNativeObject(objectType);
		}

		// ICommandList implementation

		public override void open()
		{
			switch (m_State)
			{
			case CommandListState.OPEN:
				error("Cannot open a command list that is already open");
				return;
			case CommandListState.CLOSED:
				if (m_IsImmediate)
				{
					error("An immediate command list cannot be abandoned and must be executed before it is re-opened");
					return;
				}
				else
				{
					warning("A command list should be executed before it is reopened");
					break;
				}
			case CommandListState.INITIAL:
			default:
				break;
			}

			if (m_IsImmediate)
			{
				if (++m_Device.[Friend]m_NumOpenImmediateCommandLists > 1)
				{
					error("Two or more immediate command lists cannot be open at the same time");
					--m_Device.[Friend]m_NumOpenImmediateCommandLists;
					return;
				}
			}

			m_CommandList.open();

			m_State = CommandListState.OPEN;
			m_GraphicsStateSet = false;
			m_ComputeStateSet = false;
			m_MeshletStateSet = false;
		}
		public override void close()
		{
			switch (m_State)
			{
			case CommandListState.INITIAL:
				error("Cannot close a command list before it is opened");
				return;
			case CommandListState.CLOSED:
				error("Cannot close a command list that is already closed");
				return;
			case CommandListState.OPEN:
			default:
				break;
			}

			if (m_IsImmediate)
			{
				--m_Device.[Friend]m_NumOpenImmediateCommandLists;
			}

			m_CommandList.close();

			m_State = CommandListState.CLOSED;
			m_GraphicsStateSet = false;
			m_ComputeStateSet = false;
			m_MeshletStateSet = false;
		}

		public override void clearState()
		{
			if (!requireOpenState())
				return;

			m_GraphicsStateSet = false;
			m_ComputeStateSet = false;
			m_MeshletStateSet = false;
			m_RayTracingStateSet = false;
			m_PushConstantsSet = false;

			m_CommandList.clearState();
		}

		public override void clearTextureFloat(ITexture t, TextureSubresourceSet subresources, Color clearColor)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "clearTextureFloat"))
				return;

			readonly ref TextureDesc textureDesc = ref t.getDesc();

			readonly ref FormatInfo formatInfo = ref getFormatInfo(textureDesc.format);
			if (formatInfo.hasDepth || formatInfo.hasStencil)
			{
				String message = scope $"Texture {utils.DebugNameToString(textureDesc.debugName)} cannot be cleared with clearTextureFloat because it's a depth-stencil texture. Use clearDepthStencilTexture instead.";
				error(message);
				return;
			}

			if (formatInfo.kind == FormatKind.Integer)
			{
				String message = scope $"Texture {utils.DebugNameToString(textureDesc.debugName)} cannot be cleared with clearTextureFloat because it's an integer texture. Use clearTextureUInt instead.";
				error(message);
				return;
			}

			if (!textureDesc.isRenderTarget && !textureDesc.isUAV)
			{
				String message = scope $"Texture {utils.DebugNameToString(textureDesc.debugName)} cannot be cleared with clearTextureFloat because it was created with both isRenderTarget = false and isUAV = false.";
				error(message);
				return;
			}

			m_CommandList.clearTextureFloat(t, subresources, clearColor);
		}
		public override void clearDepthStencilTexture(ITexture t, TextureSubresourceSet subresources, bool clearDepth, float depth, bool clearStencil, uint8 stencil)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Graphics, "clearDepthStencilTexture"))
				return;

			readonly ref FormatInfo formatInfo = ref getFormatInfo(t.getDesc().format);
			if (!formatInfo.hasDepth && !formatInfo.hasStencil)
			{
				String message = scope $"Texture {utils.DebugNameToString(t.getDesc().debugName)} cannot be cleared with clearDepthStencilTexture because it's not a depth-stencil texture. Use clearTextureFloat or clearTextureUInt instead.";
				error(message);
				return;
			}

			if (!t.getDesc().isRenderTarget)
			{
				String message = scope $"Texture {utils.DebugNameToString(t.getDesc().debugName)} cannot be cleared with clearDepthStencilTexture because it was created with isRenderTarget = false.";
				error(message);
				return;
			}

			m_CommandList.clearDepthStencilTexture(t, subresources, clearDepth, depth, clearStencil, stencil);
		}
		public override void clearTextureUInt(ITexture t, TextureSubresourceSet subresources, uint32 clearColor)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "clearTextureUInt"))
				return;

			readonly ref TextureDesc textureDesc = ref t.getDesc();

			readonly ref FormatInfo formatInfo = ref getFormatInfo(textureDesc.format);
			if (formatInfo.hasDepth || formatInfo.hasStencil)
			{
				String message = scope $"Texture {utils.DebugNameToString(textureDesc.debugName)} cannot be cleared with clearTextureUInt because it's a depth-stencil texture. Use clearDepthStencilTexture instead.";
				error(message);
				return;
			}

			if (formatInfo.kind != FormatKind.Integer)
			{
				String message = scope $"Texture {utils.DebugNameToString(textureDesc.debugName)} cannot be cleared with clearTextureUInt because it's not an integer texture. Use clearTextureFloat instead.";
				error(message);
				return;
			}

			if (!textureDesc.isRenderTarget && !textureDesc.isUAV)
			{
				String message = scope $"Texture {utils.DebugNameToString(textureDesc.debugName)} cannot be cleared with clearTextureUInt because it was created with both isRenderTarget = false and isUAV = false.";
				error(message);
				return;
			}

			m_CommandList.clearTextureUInt(t, subresources, clearColor);
		}

		public override void copyTexture(ITexture dest, TextureSlice destSlice, ITexture src, TextureSlice srcSlice)
		{
			if (!requireOpenState())
				return;

			m_CommandList.copyTexture(dest, destSlice, src, srcSlice);
		}
		public override void copyTexture(IStagingTexture dest, TextureSlice destSlice, ITexture src, TextureSlice srcSlice)
		{
			if (!requireOpenState())
				return;

			m_CommandList.copyTexture(dest, destSlice, src, srcSlice);
		}
		public override void copyTexture(ITexture dest, TextureSlice destSlice, IStagingTexture src, TextureSlice srcSlice)
		{
			if (!requireOpenState())
				return;

			m_CommandList.copyTexture(dest, destSlice, src, srcSlice);
		}
		public override void writeTexture(ITexture dest, uint32 arraySlice, uint32 mipLevel, void* data, int rowPitch, int depthPitch)
		{
			if (!requireOpenState())
				return;

			if (dest.getDesc().height > 1 && rowPitch == 0)
			{
				error("writeTexture: rowPitch is 0 but dest has multiple rows");
			}

			m_CommandList.writeTexture(dest, arraySlice, mipLevel, data, rowPitch, depthPitch);
		}
		public override void resolveTexture(ITexture dest, TextureSubresourceSet dstSubresources, ITexture src, TextureSubresourceSet srcSubresources)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Graphics, "resolveTexture"))
				return;

			bool anyErrors = false;

			if (dest == null)
			{
				error("resolveTexture: dest is NULL");
				anyErrors = true;
			}

			if (src == null)
			{
				error("resolveTexture: src is NULL");
				anyErrors = true;
			}

			if (anyErrors)
				return;

			readonly ref TextureDesc dstDesc = ref dest.getDesc();
			readonly ref TextureDesc srcDesc = ref src.getDesc();

			TextureSubresourceSet dstSR = dstSubresources.resolve(dstDesc, false);
			TextureSubresourceSet srcSR = srcSubresources.resolve(srcDesc, false);

			if (dstSR.numArraySlices != srcSR.numArraySlices || dstSR.numMipLevels != srcSR.numMipLevels)
			{
				error("resolveTexture: source and destination subresource sets must resolve to sets of the same size");
				anyErrors = true;
			}

			if (dstDesc.width >> dstSR.baseMipLevel != srcDesc.width >> srcSR.baseMipLevel || dstDesc.height >> dstSR.baseMipLevel != srcDesc.height >> srcSR.baseMipLevel)
			{
				error("resolveTexture: referenced mip levels of source and destination textures must have the same dimensions");
				anyErrors = true;
			}

			if (dstDesc.sampleCount != 1)
			{
				error("resolveTexture: destination texture must not be multi-sampled");
				anyErrors = true;
			}

			if (srcDesc.sampleCount <= 1)
			{
				error("resolveTexture: source texture must be multi-sampled");
				anyErrors = true;
			}

			if (srcDesc.format != dstDesc.format)
			{
				error("resolveTexture: source and destination textures must have the same format");
				anyErrors = true;
			}

			if (anyErrors)
				return;

			m_CommandList.resolveTexture(dest, dstSubresources, src, srcSubresources);
		}

		public override void writeBuffer(IBuffer b,  void* data, int dataSize, uint64 destOffsetBytes)
		{
			if (!requireOpenState())
				return;

			if (((uint64)dataSize + destOffsetBytes) > b.getDesc().byteSize)
			{
				error("writeBuffer: dataSize + destOffsetBytes is greater than the buffer size");
				return;
			}

			if (destOffsetBytes > 0 && b.getDesc().isVolatile)
			{
				error("writeBuffer: cannot write into volatile buffers with an offset");
				return;
			}

			if (dataSize > 0x10000 && b.getDesc().isVolatile)
			{
				error("writeBuffer: cannot write more than 65535 bytes into volatile buffers");
				return;
			}

			m_CommandList.writeBuffer(b, data, dataSize, destOffsetBytes);
		}
		public override void clearBufferUInt(IBuffer b, uint32 clearValue)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "clearBufferUInt"))
				return;

			m_CommandList.clearBufferUInt(b, clearValue);
		}
		public override void copyBuffer(IBuffer dest, uint64 destOffsetBytes, IBuffer src, uint64 srcOffsetBytes, uint64 dataSizeBytes)
		{
			if (!requireOpenState())
				return;

			m_CommandList.copyBuffer(dest, destOffsetBytes, src, srcOffsetBytes, dataSizeBytes);
		}

		public override void setPushConstants(void* data, int byteSize)
		{
			if (!requireOpenState())
				return;

			if (!m_GraphicsStateSet && !m_ComputeStateSet && !m_MeshletStateSet && !m_RayTracingStateSet)
			{
				error("setPushConstants is only valid when a graphics, compute, meshlet, or ray tracing state is set");
				return;
			}

			if (byteSize > c_MaxPushConstantSize)
			{
				String message = scope $"Push constant size ({byteSize}) cannot exceed {c_MaxPushConstantSize} bytes";
				error(message);
				return;
			}

			if (byteSize != m_PipelinePushConstantSize)
			{
				String message = scope $"";

				if (m_PipelinePushConstantSize == 0)
					message.Append("The current pipeline does not expect any push constants, so the setPushConstants call is invalid.");
				else
					message.AppendF("Push constant size ({0} bytes) doesn't match the size expected by the pipeline ({} bytes)", byteSize, m_PipelinePushConstantSize);

				error(message);
				return;
			}

			m_PushConstantsSet = true;

			m_CommandList.setPushConstants(data, byteSize);
		}

		public override void setGraphicsState(GraphicsState state)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Graphics, "setGraphicsState"))
				return;

			bool anyErrors = false;
			String message = scope $"";
			message.Append("setGraphicsState: \n");

			if (state.pipeline == null)
			{
				message.Append("pipeline is NULL.\n");
				anyErrors = true;
			}

			if (state.framebuffer == null)
			{
				message.Append("framebuffer is NULL.\n");
				anyErrors = true;
			}

			if (state.indexBuffer.buffer != null && !state.indexBuffer.buffer.getDesc().isIndexBuffer)
			{
				message.AppendF("Cannot use buffer '{0}' as an index buffer because it does not have the isIndexBuffer flag set.\n", utils.DebugNameToString(state.indexBuffer.buffer.getDesc().debugName));
				anyErrors = true;
			}

			for (int index = 0; index < state.vertexBuffers.Count; index++)
			{
				readonly /*ref*/ VertexBufferBinding vb = /*ref*/ state.vertexBuffers[index];

				if (vb.buffer == null)
				{
					message.AppendF("Vertex buffer in slot {0} is NULL.\n", index);
					anyErrors = true;
				}
				else if (!vb.buffer.getDesc().isVertexBuffer)
				{
					message.AppendF("Buffer '{0}' bound to vertex buffer slot {1} cannot be used as a vertex buffer because it does not have the isVertexBuffer flag set.\n",
						utils.DebugNameToString(vb.buffer.getDesc().debugName),
						index);
					anyErrors = true;
				}
			}

			if (state.indirectParams != null && !state.indirectParams.getDesc().isDrawIndirectArgs)
			{
				message.AppendF("Cannot use buffer '{}' as a DrawIndirect argument buffer because it does not have the isDrawIndirectArgs flag set.\n", utils.DebugNameToString(state.indirectParams.getDesc().debugName));
				anyErrors = true;
			}

			if (anyErrors)
			{
				error(message);
				return;
			}

			if (!validateBindingSetsAgainstLayouts(state.pipeline.getDesc().bindingLayouts, state.bindings))
				anyErrors = true;

			if (state.framebuffer.getFramebufferInfo() != state.pipeline.getFramebufferInfo())
			{
				message.Append("The framebuffer used in the draw call does not match the framebuffer used to create the pipeline.\nWidth, height, and formats of the framebuffers must match.\n");
				anyErrors = true;
			}

			if (anyErrors)
			{
				error(message);
				return;
			}

			evaluatePushConstantSize(state.pipeline.getDesc().bindingLayouts);

			m_CommandList.setGraphicsState(state);

			m_GraphicsStateSet = true;
			m_ComputeStateSet = false;
			m_MeshletStateSet = false;
			m_RayTracingStateSet = false;
			m_PushConstantsSet = false;
			m_CurrentGraphicsState = state;
		}

		public override void draw(DrawArguments args)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Graphics, "draw"))
				return;

			if (!m_GraphicsStateSet)
			{
				error("Graphics state is not set before a draw call.\nNote that setting compute state invalidates the graphics state.");
				return;
			}

			if (!validatePushConstants("graphics", "setGraphicsState"))
				return;

			m_CommandList.draw(args);
		}

		public override void drawIndexed(DrawArguments args)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Graphics, "drawIndexed"))
				return;

			if (!m_GraphicsStateSet)
			{
				error("Graphics state is not set before a drawIndexed call.\nNote that setting compute state invalidates the graphics state.");
				return;
			}

			if (m_CurrentGraphicsState.indexBuffer.buffer == null)
			{
				error("Index buffer is not set before a drawIndexed call");
				return;
			}

			if (!validatePushConstants("graphics", "setGraphicsState"))
				return;

			m_CommandList.drawIndexed(args);
		}

		public override void drawIndirect(uint32 offsetBytes)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Graphics, "drawIndirect"))
				return;

			if (!m_GraphicsStateSet)
			{
				error("Graphics state is not set before a drawIndirect call.\nNote that setting compute state invalidates the graphics state.");
				return;
			}

			if (!validatePushConstants("graphics", "setGraphicsState"))
				return;

			m_CommandList.drawIndirect(offsetBytes);
		}

		public override void setComputeState(ComputeState state)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "setComputeState"))
				return;

			bool anyErrors = false;
			String message = scope $"";
			message.Append("setComputeState: \n");

			if (state.pipeline == null)
			{
				message.Append("pipeline is NULL.\n");
				anyErrors = true;
			}

			if (state.indirectParams != null && !state.indirectParams.getDesc().isDrawIndirectArgs)
			{
				message.AppendF("Cannot use buffer '{0}' as a DispatchIndirect argument buffer because it does not have the isDrawIndirectArgs flag set.\n", utils.DebugNameToString(state.indirectParams.getDesc().debugName));
				anyErrors = true;
			}

			if (anyErrors)
			{
				error(message);
				return;
			}

			if (anyErrors)
				return;

			if (!validateBindingSetsAgainstLayouts(state.pipeline.getDesc().bindingLayouts, state.bindings))
				anyErrors = true;

			if (anyErrors)
				return;

			evaluatePushConstantSize(state.pipeline.getDesc().bindingLayouts);

			m_CommandList.setComputeState(state);

			m_GraphicsStateSet = false;
			m_ComputeStateSet = true;
			m_MeshletStateSet = false;
			m_RayTracingStateSet = false;
			m_PushConstantsSet = false;
			m_CurrentComputeState = state;
		}
		public override void dispatch(uint32 groupsX, uint32 groupsY /*= 1*/, uint32 groupsZ /*= 1*/)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "dispatch"))
				return;

			if (!m_ComputeStateSet)
			{
				error("Compute state is not set before a dispatch call.\nNote that setting graphics state invalidates the compute state.");
				return;
			}

			if (!validatePushConstants("compute", "setComputeState"))
				return;

			m_CommandList.dispatch(groupsX, groupsY, groupsZ);
		}
		public override void dispatchIndirect(uint32 offsetBytes)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "dispatchIndirect"))
				return;

			if (!m_ComputeStateSet)
			{
				error("Compute state is not set before a dispatchIndirect call.\nNote that setting graphics state invalidates the compute state.");
				return;
			}

			if (m_CurrentComputeState.indirectParams == null)
			{
				error("Indirect params buffer is not set before a dispatchIndirect call.");
				return;
			}

			if (!validatePushConstants("compute", "setComputeState"))
				return;

			m_CommandList.dispatchIndirect(offsetBytes);
		}

		public override void setMeshletState(MeshletState state)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Graphics, "setMeshletState"))
				return;

			bool anyErrors = false;
			if (state.pipeline == null)
			{
				error("MeshletState.pipeline is NULL");
				anyErrors = true;
			}

			if (anyErrors)
				return;

			if (!validateBindingSetsAgainstLayouts(state.pipeline.getDesc().bindingLayouts, state.bindings))
				anyErrors = true;

			if (anyErrors)
				return;

			evaluatePushConstantSize(state.pipeline.getDesc().bindingLayouts);

			m_CommandList.setMeshletState(state);

			m_GraphicsStateSet = false;
			m_ComputeStateSet = false;
			m_MeshletStateSet = true;
			m_RayTracingStateSet = false;
			m_PushConstantsSet = false;
			m_CurrentMeshletState = state;
		}
		public override void dispatchMesh(uint32 groupsX, uint32 groupsY /*= 1*/, uint32 groupsZ /*= 1*/)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Graphics, "dispatchMesh"))
				return;

			if (!m_MeshletStateSet)
			{
				error("Meshlet state is not set before a dispatchMesh call.\nNote that setting graphics or compute state invalidates the meshlet state.");
				return;
			}

			if (!validatePushConstants("meshlet", "setMeshletState"))
				return;

			m_CommandList.dispatchMesh(groupsX, groupsY, groupsZ);
		}

		public override void setRayTracingState(nvrhi.rt.State state)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "setRayTracingState"))
				return;

			evaluatePushConstantSize(state.shaderTable.getPipeline().getDesc().globalBindingLayouts);

			m_CommandList.setRayTracingState(state);

			m_GraphicsStateSet = false;
			m_ComputeStateSet = false;
			m_MeshletStateSet = true;
			m_RayTracingStateSet = true;
			m_PushConstantsSet = false;
			m_CurrentRayTracingState = state;
		}
		public override void dispatchRays(nvrhi.rt.DispatchRaysArguments args)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "dispatchRays"))
				return;

			if (!m_RayTracingStateSet)
			{
				error("Ray tracing state is not set before a dispatchRays call.\nNote that setting graphics or compute state invalidates the ray tracing state.");
				return;
			}

			if (!validatePushConstants("ray tracing", "setRayTracingState"))
				return;

			m_CommandList.dispatchRays(args);
		}

		public override void buildBottomLevelAccelStruct(nvrhi.rt.IAccelStruct @as, nvrhi.rt.GeometryDesc* pGeometries, int numGeometries, AccelStructBuildFlags buildFlags)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "buildBottomLevelAccelStruct"))
				return;

			nvrhi.rt.IAccelStruct underlyingAS = @as;

			AccelStructWrapper wrapper = @as as AccelStructWrapper;
			if (wrapper != null)
			{
				underlyingAS = wrapper.getUnderlyingObject();

				if (wrapper.isTopLevel)
				{
					error("Cannot perform buildBottomLevelAccelStruct on a top-level AS");
					return;
				}

				for (int i = 0; i < numGeometries; i++)
				{
					/*readonly ref*/ var geom = ref pGeometries[i];

					if (geom.geometryType == nvrhi.rt.GeometryType.Triangles)
					{
						/*readonly ref*/ var triangles = ref geom.geometryData.triangles;

						if (triangles.indexFormat != Format.UNKNOWN)
						{
							switch (triangles.indexFormat) // NOLINT(clang-diagnostic-switch-enum)
							{
							case Format.R8_UINT:
								if (m_Device.getGraphicsAPI() != GraphicsAPI.VULKAN)
								{
									String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has index format R8_UINT which is only supported on Vulkan";
									error(message);
									return;
								}
								break;
							case Format.R16_UINT: fallthrough;
							case Format.R32_UINT:
								break;
							default:
								{
									String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has unsupported index format: {utils.FormatToString(triangles.indexFormat)}";
									error(message);
									return;
								}
							}

							if (triangles.indexBuffer == null)
							{
								String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has a NULL index buffer but indexFormat is {utils.FormatToString(triangles.indexFormat)}";
								error(message);
								return;
							}

							readonly ref BufferDesc indexBufferDesc = ref triangles.indexBuffer.getDesc();
							if (!indexBufferDesc.isAccelStructBuildInput)
							{
								String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has index buffer = {utils.DebugNameToString(indexBufferDesc.debugName)} which does not have the isAccelStructBuildInput flag set";
								error(message);
								return;
							}

							readonly var indexSize = triangles.indexCount * getFormatInfo(triangles.indexFormat).bytesPerBlock;
							if (triangles.indexOffset + indexSize > indexBufferDesc.byteSize)
							{
								String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} points at {indexSize} bytes of index data at offset {triangles.indexOffset} in buffer {utils.DebugNameToString(indexBufferDesc.debugName)} whose size is {indexBufferDesc.byteSize}, which will result in a buffer overrun";
								error(message);
								return;
							}

							if ((triangles.indexCount % 3) != 0)
							{
								String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has indexCount = {triangles.indexCount}, which is not a multiple of 3";
								error(message);
								return;
							}
						}
						else
						{
							if (triangles.indexCount != 0 || triangles.indexBuffer != null)
							{
								String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has indexFormat = UNKNOWN but nonzero indexCount = {triangles.indexCount}";
								error(message);
								return;
							}

							if (triangles.indexBuffer != null)
							{
								String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has indexFormat = UNKNOWN but non-NULL indexBuffer = {utils.DebugNameToString(triangles.indexBuffer.getDesc().debugName)}";
								error(message);
								return;
							}
						}

						switch (triangles.vertexFormat) // NOLINT(clang-diagnostic-switch-enum)
						{
						case Format.RG32_FLOAT: fallthrough;
						case Format.RGB32_FLOAT: fallthrough;
						case Format.RG16_FLOAT: fallthrough;
						case Format.RGBA16_FLOAT: fallthrough;
						case Format.RG16_SNORM: fallthrough;
						case Format.RGBA16_SNORM: fallthrough;
						case Format.RGBA16_UNORM: fallthrough;
						case Format.RG16_UNORM: fallthrough;
						case Format.R10G10B10A2_UNORM: fallthrough;
						case Format.RGBA8_UNORM: fallthrough;
						case Format.RG8_UNORM: fallthrough;
						case Format.RGBA8_SNORM: fallthrough;
						case Format.RG8_SNORM:
							break;
						default:
							{
								String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has unsupported vertex format: {utils.FormatToString(triangles.indexFormat)}";
								error(message);
								return;
							}
						}

						if (triangles.vertexBuffer == null)
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has NULL vertex buffer";
							error(message);
							return;
						}

						if (triangles.vertexStride == 0)
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has vertexStride = 0";
							error(message);
							return;
						}

						if ((triangles.indexFormat == Format.UNKNOWN) && (triangles.vertexCount % 3) != 0)
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has indexFormat = UNKNOWN and vertexCount = {triangles.vertexCount}, which is not a multiple of 3";
							error(message);
							return;
						}

						readonly ref BufferDesc vertexBufferDesc = ref triangles.vertexBuffer.getDesc();
						if (!vertexBufferDesc.isAccelStructBuildInput)
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has vertex buffer = {utils.DebugNameToString(vertexBufferDesc.debugName)} which does not have the isAccelStructBuildInput flag set";
							error(message);
							return;
						}

						readonly var vertexDataSize = triangles.vertexCount * triangles.vertexStride;
						if (triangles.vertexOffset + vertexDataSize > vertexBufferDesc.byteSize)
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} points at {vertexDataSize} bytes of vertex data at offset {triangles.vertexOffset} in buffer {utils.DebugNameToString(vertexBufferDesc.debugName)} whose size is {vertexBufferDesc.byteSize}, which will result in a buffer overrun";
							error(message);
							return;
						}
					}
					else // AABBs
					{
						/*readonly ref*/ var aabbs = ref geom.geometryData.aabbs;

						if (aabbs.buffer == null)
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has NULL AABB data buffer";
							error(message);
							return;
						}

						readonly ref BufferDesc aabbBufferDesc = ref aabbs.buffer.getDesc();
						if (!aabbBufferDesc.isAccelStructBuildInput)
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has AABB data buffer = {utils.DebugNameToString(aabbBufferDesc.debugName)} which does not have the isAccelStructBuildInput flag set";
							error(message);
							return;
						}

						if (aabbs.count > 1 && aabbs.stride < sizeof(nvrhi.rt.GeometryAABB))
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} has AABB stride = {aabbs.stride} which is less than the size of one AABB ({sizeof(nvrhi.rt.GeometryAABB)} bytes)";
							error(message);
							return;
						}

						readonly var aabbDataSize = aabbs.count * aabbs.stride;
						if (aabbs.offset + aabbDataSize > aabbBufferDesc.byteSize)
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} points at {aabbDataSize} bytes of AABB data at offset {aabbs.offset} in buffer {utils.DebugNameToString(aabbBufferDesc.debugName)} whose size is {aabbBufferDesc.byteSize}, which will result in a buffer overrun";
							error(message);
							return;
						}

						if (geom.useTransform)
						{
							String message = scope $"BLAS {utils.DebugNameToString(@as.getDesc().debugName)} build geometry {i} is of type AABB but has useTransform = true, which is unsupported, and the transform will be ignored";
							m_MessageCallback.message(MessageSeverity.Warning, message);
						}
					}
				}

				if ((buildFlags & nvrhi.rt.AccelStructBuildFlags.PerformUpdate) != 0)
				{
					if (!wrapper.allowUpdate)
					{
						String message = scope $"Cannot perform an update on BLAS {utils.DebugNameToString(@as.getDesc().debugName)} that was not created with the AllowUpdate flag";
						error(message);
						return;
					}

					if (!wrapper.wasBuilt)
					{
						String message = scope $"Cannot perform an update on BLAS {utils.DebugNameToString(@as.getDesc().debugName)} before the same BLAS was initially built";
						error(message);
						return;
					}

					if (numGeometries != wrapper.buildGeometries.Count)
					{
						String message = scope $"Cannot perform an update on BLAS {utils.DebugNameToString(@as.getDesc().debugName)} with {numGeometries} geometries when this BLAS was built with {wrapper.buildGeometries.Count} geometries";
						error(message);
						return;
					}

					for (int i = 0; i < numGeometries; i++)
					{
						/*readonly ref*/ var before = ref wrapper.buildGeometries[i];
						/*readonly ref*/ var after = ref pGeometries[i];

						if (before.geometryType != after.geometryType)
						{
							String message = scope $"Cannot perform an update on BLAS {utils.DebugNameToString(@as.getDesc().debugName)} with mismatching geometry types in slot {i}";
							error(message);
							return;
						}

						if (before.geometryType == nvrhi.rt.GeometryType.Triangles)
						{
							uint32 primitivesBefore = (before.geometryData.triangles.vertexFormat == Format.UNKNOWN)
								? before.geometryData.triangles.vertexCount
								: before.geometryData.triangles.indexCount;

							uint32 primitivesAfter = (after.geometryData.triangles.vertexFormat == Format.UNKNOWN)
								? after.geometryData.triangles.vertexCount
								: after.geometryData.triangles.indexCount;

							primitivesBefore /= 3;
							primitivesAfter /= 3;

							if (primitivesBefore != primitivesAfter)
							{
								String message = scope $"Cannot perform an update on BLAS {utils.DebugNameToString(@as.getDesc().debugName)} with mismatching triangle counts in geometry slot {i}: built with {primitivesBefore} triangles, updating with {primitivesAfter} triangles";
								error(message);
								return;
							}
						}
						else // AABBs
						{
							uint32 aabbsBefore = before.geometryData.aabbs.count;
							uint32 aabbsAfter = after.geometryData.aabbs.count;

							if (aabbsBefore != aabbsAfter)
							{
								String message = scope $"Cannot perform an update on BLAS {utils.DebugNameToString(@as.getDesc().debugName)} with mismatching AABB counts in geometry slot {i}:built with {aabbsBefore} AABBs, updating with {aabbsAfter} AABBs";
								error(message);
								return;
							}
						}
					}
				}

				if (wrapper.allowCompaction && wrapper.wasBuilt)
				{
					String message = scope $"Cannot rebuild BLAS {utils.DebugNameToString(@as.getDesc().debugName)} that has the AllowCompaction flag set";
					error(message);
					return;
				}

				wrapper.wasBuilt = true;
				wrapper.buildGeometries.Assign(pGeometries, numGeometries);
			}

			m_CommandList.buildBottomLevelAccelStruct(underlyingAS, pGeometries, numGeometries, buildFlags);
		}
		public override void compactBottomLevelAccelStructs()
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "compactBottomLevelAccelStructs"))
				return;

			m_CommandList.compactBottomLevelAccelStructs();
		}
		public override void buildTopLevelAccelStruct(nvrhi.rt.IAccelStruct @as, nvrhi.rt.InstanceDesc* pInstances, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "buildTopLevelAccelStruct"))
				return;

			if (@as == null)
			{
				error("buildTopLevelAccelStruct: 'as' is NULL");
				return;
			}

			List<nvrhi.rt.InstanceDesc> patchedInstances = scope .();
			patchedInstances.Assign(pInstances, numInstances);

			for (var instance in ref patchedInstances)
			{
				instance.bottomLevelAS = checked_cast<nvrhi.rt.IAccelStruct, IResource>(unwrapResource(instance.bottomLevelAS));
			}

			nvrhi.rt.IAccelStruct underlyingAS = @as;

			AccelStructWrapper wrapper = @as as AccelStructWrapper;
			if (wrapper != null)
			{
				underlyingAS = wrapper.getUnderlyingObject();

				if (!validateBuildTopLevelAccelStruct(wrapper, numInstances, buildFlags))
					return;

				for (int i = 0; i < numInstances; i++)
				{
					/*readonly ref*/ var instance = ref pInstances[i];

					if (instance.bottomLevelAS == null)
					{
						String message = scope $"TLAS {utils.DebugNameToString(@as.getDesc().debugName)} build instance {i} has a NULL bottomLevelAS";
						error(message);
						return;
					}

					AccelStructWrapper blasWrapper = instance.bottomLevelAS as AccelStructWrapper;
					if (blasWrapper != null)
					{
						if (blasWrapper.isTopLevel)
						{
							String message = scope $"TLAS {utils.DebugNameToString(@as.getDesc().debugName)} build instance {i} refers to another TLAS, which is unsupported";
							error(message);
							return;
						}

						if (!blasWrapper.wasBuilt)
						{
							String message = scope $"TLAS {utils.DebugNameToString(@as.getDesc().debugName)} build instance {i} refers to a BLAS which was never built";
							error(message);
							return;
						}
					}

					if (instance.instanceMask == 0)
					{
						String message = scope $"TLAS {utils.DebugNameToString(@as.getDesc().debugName)} build instance {i} has instanceMask = 0, which means the instance will never be included in any ray intersections";
						m_MessageCallback.message(MessageSeverity.Warning, message);
					}
				}

				wrapper.wasBuilt = true;
				wrapper.buildInstances = numInstances;
			}
			m_CommandList.buildTopLevelAccelStruct(underlyingAS, patchedInstances.Ptr, uint32(patchedInstances.Count), buildFlags);
		}

		public override void buildTopLevelAccelStructFromBuffer(nvrhi.rt.IAccelStruct @as, nvrhi.IBuffer instanceBuffer, uint64 instanceBufferOffset, int numInstances, nvrhi.rt.AccelStructBuildFlags buildFlags)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "buildTopLevelAccelStruct"))
				return;

			if (@as == null)
			{
				error("buildTopLevelAccelStructFromBuffer: 'as' is NULL");
				return;
			}

			if (instanceBuffer == null)
			{
				error("buildTopLevelAccelStructFromBuffer: 'instanceBuffer' is NULL");
				return;
			}

			nvrhi.rt.IAccelStruct underlyingAS = @as;

			AccelStructWrapper wrapper = @as as AccelStructWrapper;
			if (wrapper != null)
			{
				underlyingAS = wrapper.getUnderlyingObject();

				if (!validateBuildTopLevelAccelStruct(wrapper, numInstances, buildFlags))
					return;
			}

			var bufferDesc = instanceBuffer.getDesc();
			if (!bufferDesc.isAccelStructBuildInput)
			{
				String message = scope $"Buffer {utils.DebugNameToString(bufferDesc.debugName)} used in buildTopLevelAccelStructFromBuffer doesn't have the 'isAccelStructBuildInput' flag set";
				error(message);
				return;
			}

			uint64 sizeOfData = (.)numInstances * sizeof(nvrhi.rt.InstanceDesc);
			if (bufferDesc.byteSize < instanceBufferOffset + sizeOfData)
			{
				String message = scope $"Buffer {utils.DebugNameToString(bufferDesc.debugName)} used in buildTopLevelAccelStructFromBuffer is smaller than the referenced instance data: {sizeOfData} bytes used at offset {instanceBufferOffset}, buffer size is {bufferDesc.byteSize} bytes";
				error(message);
				return;
			}

			m_CommandList.buildTopLevelAccelStructFromBuffer(underlyingAS, instanceBuffer, instanceBufferOffset, numInstances, buildFlags);
		}

		public override void beginTimerQuery(ITimerQuery query)
		{
			if (!requireOpenState())
				return;

			m_CommandList.beginTimerQuery(query);
		}
		public override void endTimerQuery(ITimerQuery query)
		{
			if (!requireOpenState())
				return;

			m_CommandList.endTimerQuery(query);
		}

		public override void beginMarker(char8* name)
		{
			if (!requireOpenState())
				return;

			m_CommandList.beginMarker(name);
		}
		public override void endMarker()
		{
			if (!requireOpenState())
				return;

			m_CommandList.endMarker();
		}

		public override void setEnableAutomaticBarriers(bool enable)
		{
			if (!requireOpenState())
				return;

			m_CommandList.setEnableAutomaticBarriers(enable);
		}
		public override void setResourceStatesForBindingSet(IBindingSet bindingSet)
		{
			if (!requireOpenState())
				return;

			m_CommandList.setResourceStatesForBindingSet(bindingSet);
		}

		public override void setEnableUavBarriersForTexture(ITexture texture, bool enableBarriers)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "setEnableUavBarriersForTexture"))
				return;

			m_CommandList.setEnableUavBarriersForTexture(texture, enableBarriers);
		}
		public override void setEnableUavBarriersForBuffer(IBuffer buffer, bool enableBarriers)
		{
			if (!requireOpenState())
				return;

			if (!requireType(CommandQueue.Compute, "setEnableUavBarriersForBuffer"))
				return;

			m_CommandList.setEnableUavBarriersForBuffer(buffer, enableBarriers);
		}

		public override void beginTrackingTextureState(ITexture texture, TextureSubresourceSet subresources, ResourceStates stateBits)
		{
			if (!requireOpenState())
				return;

			m_CommandList.beginTrackingTextureState(texture, subresources, stateBits);
		}
		public override void beginTrackingBufferState(IBuffer buffer, ResourceStates stateBits)
		{
			if (!requireOpenState())
				return;

			m_CommandList.beginTrackingBufferState(buffer, stateBits);
		}

		public override void setTextureState(ITexture texture, TextureSubresourceSet subresources, ResourceStates stateBits)
		{
			if (!requireOpenState())
				return;

			m_CommandList.setTextureState(texture, subresources, stateBits);
		}
		public override void setBufferState(IBuffer buffer, ResourceStates stateBits)
		{
			if (!requireOpenState())
				return;

			m_CommandList.setBufferState(buffer, stateBits);
		}
		public override void setAccelStructState(nvrhi.rt.IAccelStruct @as, ResourceStates stateBits)
		{
			if (!requireOpenState())
				return;

			m_CommandList.setAccelStructState(checked_cast<nvrhi.rt.IAccelStruct, IResource>(unwrapResource(@as)), stateBits);
		}

		public override void setPermanentTextureState(ITexture texture, ResourceStates stateBits)
		{
			if (!requireOpenState())
				return;

			m_CommandList.setPermanentTextureState(texture, stateBits);
		}
		public override void setPermanentBufferState(IBuffer buffer, ResourceStates stateBits)
		{
			if (!requireOpenState())
				return;

			m_CommandList.setPermanentBufferState(buffer, stateBits);
		}

		public override void commitBarriers()
		{
			if (!requireOpenState())
				return;

			m_CommandList.commitBarriers();
		}

		public override ResourceStates getTextureSubresourceState(ITexture texture, ArraySlice arraySlice, MipLevel mipLevel)
		{
			if (!requireOpenState())
				return ResourceStates.Common;

			return m_CommandList.getTextureSubresourceState(texture, arraySlice, mipLevel);
		}
		public override ResourceStates getBufferState(IBuffer buffer)
		{
			if (!requireOpenState())
				return ResourceStates.Common;

			return m_CommandList.getBufferState(buffer);
		}

		public override IDevice getDevice()
		{
			return m_Device;
		}
		public override readonly ref CommandListParameters getDesc()
		{
			return ref m_CommandList.getDesc();
		}
	}
}