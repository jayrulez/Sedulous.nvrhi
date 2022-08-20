namespace nvrhi
{
	//////////////////////////////////////////////////////////////////////////
	// ICommandList
	//////////////////////////////////////////////////////////////////////////

	abstract class ICommandList :  IResource
	{
		public abstract void open();
		public abstract void close();

		// Clears the graphics state of the underlying command list object and resets the state cache.
		public abstract void clearState();

		public abstract void clearTextureFloat(ITexture t, TextureSubresourceSet subresources, Color clearColor);
		public abstract void clearDepthStencilTexture(ITexture t, TextureSubresourceSet subresources, bool clearDepth, float depth, bool clearStencil, uint8 stencil);
		public abstract void clearTextureUInt(ITexture t, TextureSubresourceSet subresources, uint32 clearColor);

		public abstract void copyTexture(ITexture dest, TextureSlice destSlice, ITexture src, TextureSlice srcSlice);
		public abstract void copyTexture(IStagingTexture dest, TextureSlice destSlice, ITexture src, TextureSlice srcSlice);
		public abstract void copyTexture(ITexture dest, TextureSlice destSlice, IStagingTexture src, TextureSlice srcSlice);
		public abstract void writeTexture(ITexture dest, uint32 arraySlice, uint32 mipLevel, void* data, int rowPitch, int depthPitch = 0);
		public abstract void resolveTexture(ITexture dest, TextureSubresourceSet dstSubresources, ITexture src, TextureSubresourceSet srcSubresources);

		public abstract void writeBuffer(IBuffer b, void* data, int dataSize, uint64 destOffsetBytes = 0);
		public abstract void clearBufferUInt(IBuffer b, uint32 clearValue);
		public abstract void copyBuffer(IBuffer dest, uint64 destOffsetBytes, IBuffer src, uint64 srcOffsetBytes, uint64 dataSizeBytes);

		// Sets the push constants block on the command list, aka "root constants" on DX12.
		// Only valid after setGraphicsState or setComputeState etc.
		public abstract void setPushConstants(void* data, int byteSize);

		public abstract void setGraphicsState(GraphicsState state);
		public abstract void draw(DrawArguments args);
		public abstract void drawIndexed(DrawArguments args);
		public abstract void drawIndirect(uint32 offsetBytes);

		public abstract void setComputeState(ComputeState state);
		public abstract void dispatch(uint32 groupsX, uint32 groupsY = 1, uint32 groupsZ = 1);
		public abstract void dispatchIndirect(uint32 offsetBytes);

		public abstract void setMeshletState(MeshletState state);
		public abstract void dispatchMesh(uint32 groupsX, uint32 groupsY = 1, uint32 groupsZ = 1);

		public abstract void setRayTracingState(nvrhi.rt.State state);
		public abstract void dispatchRays(nvrhi.rt.DispatchRaysArguments args);

		public abstract void buildBottomLevelAccelStruct(nvrhi.rt.IAccelStruct @as, nvrhi.rt.GeometryDesc* pGeometries, int numGeometries,
			nvrhi.rt.AccelStructBuildFlags buildFlags = nvrhi.rt.AccelStructBuildFlags.None);
		public abstract void compactBottomLevelAccelStructs();
		public abstract void buildTopLevelAccelStruct(nvrhi.rt.IAccelStruct @as, nvrhi.rt.InstanceDesc* pInstances, int numInstances,
			nvrhi.rt.AccelStructBuildFlags buildFlags = nvrhi.rt.AccelStructBuildFlags.None);

		// A version of buildTopLevelAccelStruct that takes the instance data from a buffer on the GPU.
		// The buffer must be pre-filled with nvrhi.rt.InstanceDesc structures using a copy operation or a shader.
		// No validation on the buffer contents is performed by NVRHI, and no state or liveness tracking for the referenced BLAS'es.
		public abstract void buildTopLevelAccelStructFromBuffer(nvrhi.rt.IAccelStruct @as, nvrhi.IBuffer instanceBuffer, uint64 instanceBufferOffset, int numInstances,
			nvrhi.rt.AccelStructBuildFlags buildFlags = nvrhi.rt.AccelStructBuildFlags.None);

		public abstract void beginTimerQuery(ITimerQuery query);
		public abstract void endTimerQuery(ITimerQuery query);

		// Command list range markers
		public abstract void beginMarker(char8* name);
		public abstract void endMarker();

		// Enables or disables the automatic barrier placement on set[...]State, copy, write, and clear operations.
		// By default, automatic barriers are enabled, but can be optionally disabled to improve CPU performance and/or specific barrier placement.
		// When automatic barriers are disabled, it is application's responsibility to set correct states for all used resources.
		public abstract void setEnableAutomaticBarriers(bool enable);

		// Sets the necessary resource states for all non-permanent resources used in the binding set.
		public abstract void setResourceStatesForBindingSet(IBindingSet bindingSet);

		// Sets the necessary resource states for all targets of the framebuffer.
		public void setResourceStatesForFramebuffer(IFramebuffer framebuffer)
		{
			readonly ref FramebufferDesc desc = ref framebuffer.getDesc();

			for (readonly ref FramebufferAttachment attachment in ref desc.colorAttachments)
			{
				setTextureState(attachment.texture, attachment.subresources,
					ResourceStates.RenderTarget);
			}

			if (desc.depthAttachment.valid())
			{
				setTextureState(desc.depthAttachment.texture, desc.depthAttachment.subresources,
					desc.depthAttachment.isReadOnly ? ResourceStates.DepthRead : ResourceStates.DepthWrite);
			}
		}

		// Tells the D3D12/VK backend whether UAV barriers should be used for the given texture or buffer between draw calls.
		// A barrier should still be placed before the first draw call in the group and after the last one.
		public abstract void setEnableUavBarriersForTexture(ITexture texture, bool enableBarriers);
		public abstract void setEnableUavBarriersForBuffer(IBuffer buffer, bool enableBarriers);

		// Informs the command list of the state of a texture subresource or buffer prior to command list execution
		public abstract void beginTrackingTextureState(ITexture texture, TextureSubresourceSet subresources, ResourceStates stateBits);
		public abstract void beginTrackingBufferState(IBuffer buffer, ResourceStates stateBits);

		// Resource state transitions - these put barriers into the pending list. Call commitBarriers() after.
		public abstract void setTextureState(ITexture texture, TextureSubresourceSet subresources, ResourceStates stateBits);
		public abstract void setBufferState(IBuffer buffer, ResourceStates stateBits);
		public abstract void setAccelStructState(nvrhi.rt.IAccelStruct @as, ResourceStates stateBits);

		// Permanent resource state transitions - these make resource usage cheaper by excluding it from state tracking in the future.
		// Like setTexture/BufferState, these methods put barriers into the pending list. Call commitBarriers() after.
		public abstract void setPermanentTextureState(ITexture texture, ResourceStates stateBits);
		public abstract void setPermanentBufferState(IBuffer buffer, ResourceStates stateBits);

		// Flushes the barriers from the pending list into the GAPI command list.
		public abstract void commitBarriers();

		// Returns the current tracked state of a texture subresource or a buffer.
		public abstract ResourceStates getTextureSubresourceState(ITexture texture, ArraySlice arraySlice, MipLevel mipLevel);
		public abstract ResourceStates getBufferState(IBuffer buffer);

		// Returns the owning device, does NOT call AddRef on it
		public abstract IDevice getDevice();
		public abstract readonly ref CommandListParameters getDesc();
	}

	typealias CommandListHandle = RefCountPtr<ICommandList>;
}